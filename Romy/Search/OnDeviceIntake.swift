import Foundation
import FoundationModels

/// 一言の解釈を端末内のApple Intelligenceで行う。文は端末の外へ送らない。
///
/// 端末内のモデルは小さく、数値をそのまま出させると書いていない数字を埋めたり、
/// 同じ数字を徒歩・休憩・全体のすべてに入れたりする（2026-11-17の検証）。
/// そのため数字は通常のコードが原文から取り出し、AIには各時間の役割の分類と
/// 料理名・店の種類の抜き出しだけを任せる。結果は原文と照合してから採用する。
enum OnDeviceIntake {
    static var isAvailable: Bool {
        if case .available = SystemLanguageModel.default.availability { return true }
        return false
    }

    /// 端末内モデルで解釈する。使えない端末・生成の失敗ではnilを返し、呼び出し側が扱いを決める。
    static func interpret(_ text: String) async -> ScenePreferences? {
        guard isAvailable else { return nil }
        // 起動直後の1回目は、安全確認用のモデルの準備が間に合わず失敗することがある（Simulatorで確認）。
        // 準備後は同じ文で成功するため、1回だけやり直す。それでも失敗したら未反映として扱う。
        for _ in 0..<2 {
            guard !Task.isCancelled else { return nil }
            let session = LanguageModelSession(instructions: instructions)
            if let reading = try? await session.respond(
                to: text, generating: IntakeReading.self,
                options: GenerationOptions(samplingMode: .greedy)
            ).content {
                return preferences(from: reading, text: text)
            }
        }
        return nil
    }

    /// AIの読み取りを原文と照合し、検証済みの条件にする。モデルを使わずにテストできるよう分けている。
    static func preferences(from reading: IntakeReading, text: String) -> ScenePreferences {
        var result = ScenePreferences()
        let mentions = timeMentions(in: text)
        if reading.roles.count == mentions.count {
            // 範囲外の数字は条件にせず未反映へ回す（中継の解釈と同じ扱い。範囲はScenePreferences.isValid）。
            for (role, mention) in zip(reading.roles, mentions) {
                let minutes = mention.minutes
                switch role {
                case .walk where result.walkMinutes == nil && (1...30).contains(minutes):
                    result.walkMinutes = minutes
                case .rest where result.restMinutes == nil && (5...240).contains(minutes):
                    result.restMinutes = minutes
                case .total where result.totalMinutes == nil && (5...300).contains(minutes):
                    result.totalMinutes = minutes
                default: result.unhandled.append(mention.phrase)
                }
            }
        } else {
            // 時間の数と役割の数が合わないときは対応が分からないため、推測で割り当てず未反映にする。
            result.unhandled += mentions.map(\.phrase)
        }

        // 原文に書いていない料理名（「none」などの埋め草を含む）は採用しない。
        let food = reading.food.trimmingCharacters(in: .whitespacesAndNewlines)
        if !food.isEmpty, food.count <= 50, text.contains(food) { result.query = food }

        // 店の種類は原文に種類の語があるときだけ採用する。「抹茶のスイーツ」をカフェへ読み替えない。
        if let kind = reading.kind.category, let words = kindWords[kind],
           let word = words.first(where: text.contains) {
            result.category = kind
            if result.query == nil { result.query = word }
        }

        let others = reading.unhandled
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && $0.lowercased() != "none" && text.contains($0) }
        for phrase in others where !result.unhandled.contains(phrase) && phrase != result.query {
            result.unhandled.append(phrase)
        }
        result.unhandled = Array(result.unhandled.prefix(8))
        return result
    }

    /// 原文から「N分」「N時間」「N時間半」を出てくる順に取り出す。範囲外の数字は検証で落ちる。
    static func timeMentions(in text: String) -> [(phrase: String, minutes: Int)] {
        let regex = /([0-9０-９]+)\s*(時間半|時間|分)/
        return text.matches(of: regex).compactMap { match in
            let digits = String(match.output.1).applyingTransform(.fullwidthToHalfwidth, reverse: false)
            guard let digits, let value = Int(digits) else { return nil }
            let minutes = switch match.output.2 {
            case "分": value
            case "時間半": value * 60 + 30
            default: value * 60
            }
            return (String(match.output.0), minutes)
        }
    }

    private static let kindWords: [String: [String]] = [
        "cafe": ["カフェ", "喫茶", "コーヒー"],
        "restaurant": ["レストラン", "食堂", "定食"],
        "bakery": ["パン屋", "ベーカリー", "パン"]
    ]

    private static let instructions = """
    旅行中の短い希望を読み、時間の表現それぞれの役割を分類する。
    walk: 歩ける時間の上限（歩くのは10分まで、徒歩5分以内）
    rest: 店で休む・座る・ゆっくりする時間（30分休みたい、1時間ゆっくり）
    total: 移動も含めて使える全体の時間（全体で30分、あと45分で戻る、40分しかない、1時間で戻る）
    unclear: どれか分からない
    例:「30分休みたい」→[rest]、「あと45分で戻らないと」→[total]、「歩くのは10分まで、30分休憩」→[walk, rest]、「疲れた」→[]
    料理名・店の種類は原文に書いてあるときだけ入れる。推測で補わない。
    """
}

/// 端末内モデルに出させる読み取り。数値は含めず、役割と原文の語だけにする。
@Generable
struct IntakeReading {
    @Generable
    enum Role { case walk, rest, total, unclear }

    @Generable
    enum Kind {
        case none, cafe, restaurant, bakery

        var category: String? {
            switch self {
            case .none: nil
            case .cafe: "cafe"
            case .restaurant: "restaurant"
            case .bakery: "bakery"
            }
        }
    }

    @Guide(description: "原文の時間の表現それぞれの役割。原文に出てくる順。時間の表現がなければ空")
    var roles: [Role]
    @Guide(description: "食べたい料理・食べ物の名前。なければ空文字")
    var food: String
    @Guide(description: "店の種類。原文に書いていなければnone")
    var kind: Kind
    @Guide(description: "時間・料理・店の種類以外の希望（静か、安い、近いなど）の原文。なければ空")
    var unhandled: [String]
}
