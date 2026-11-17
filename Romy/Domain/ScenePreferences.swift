import Foundation

/// 一言の解釈結果。時間や距離をAIに計算させず、検証済みの条件として受け取る。
struct ScenePreferences: Codable, Equatable {
    var query: String?
    var category: String?
    var walkMinutes: Int?
    var restMinutes: Int?
    var totalMinutes: Int?
    var unhandled: [String] = []

    var isValid: Bool {
        let allowedCategory = category.map { ["cafe", "restaurant", "bakery"].contains($0) } ?? true
        return (query?.count ?? 0) <= 50 && allowedCategory
            && (walkMinutes.map { (1...30).contains($0) } ?? true)
            && (restMinutes.map { (5...240).contains($0) } ?? true)
            && (totalMinutes.map { (5...300).contains($0) } ?? true)
            && unhandled.count <= 8
    }

    var captions: [String] {
        var values = [String]()
        if let query { values.append(query) }
        if let walkMinutes { values.append("徒歩\(walkMinutes)分以内") }
        if let restMinutes { values.append("休憩\(restMinutes)分") }
        if let totalMinutes { values.append("全体で\(totalMinutes)分") }
        return values
    }
}
