import Testing
@testable import Romy

/// 端末内モデルの読み取りを原文と照合する処理の確認。モデル自体は呼ばない。
struct OnDeviceIntakeTests {
    private func reading(_ roles: [IntakeReading.Role] = [], food: String = "",
                         kind: IntakeReading.Kind = .none, unhandled: [String] = []) -> IntakeReading {
        IntakeReading(roles: roles, food: food, kind: kind, unhandled: unhandled)
    }

    @Test func takesNumbersFromTheTextInOrder() {
        let mentions = OnDeviceIntake.timeMentions(in: "徒歩５分以内で30分休憩、全体1時間半")
        #expect(mentions.map(\.minutes) == [5, 30, 90])
        #expect(mentions.map(\.phrase) == ["５分", "30分", "1時間半"])
    }

    @Test func assignsEachTimeToItsRole() {
        let text = "徒歩5分以内で30分休憩、全体1時間半"
        let result = OnDeviceIntake.preferences(from: reading([.walk, .rest, .total]), text: text)
        #expect(result.walkMinutes == 5)
        #expect(result.restMinutes == 30)
        #expect(result.totalMinutes == 90)
        #expect(result.isValid)
    }

    @Test func restAndTotalStaySeparate() {
        let rest = OnDeviceIntake.preferences(from: reading([.rest]), text: "30分休みたい")
        #expect(rest.restMinutes == 30 && rest.totalMinutes == nil)
        let total = OnDeviceIntake.preferences(from: reading([.total]), text: "全体で30分しかない")
        #expect(total.totalMinutes == 30 && total.restMinutes == nil)
    }

    @Test func mismatchedRolesAreNotGuessed() {
        // AIが数字の数と違う役割を返したら、どれにも割り当てず未反映として見せる。
        let result = OnDeviceIntake.preferences(from: reading([.walk, .rest, .total]), text: "30分休みたい")
        #expect(result.walkMinutes == nil && result.restMinutes == nil && result.totalMinutes == nil)
        #expect(result.unhandled == ["30分"])
    }

    @Test func unclearTimeIsShownAsUnhandled() {
        let result = OnDeviceIntake.preferences(from: reading([.unclear]), text: "40分くらい")
        #expect(result.unhandled == ["40分"])
    }

    @Test func foodMustAppearInTheText() {
        let kept = OnDeviceIntake.preferences(from: reading(food: "ラーメン"), text: "歩くのは10分まで、ラーメン")
        #expect(kept.query == "ラーメン")
        let filler = OnDeviceIntake.preferences(from: reading(food: "none"), text: "30分休みたい")
        #expect(filler.query == nil)
    }

    @Test func kindIsKeptOnlyWhenWritten() {
        // 食べ物を一般のカフェへ読み替えない。
        let sweets = OnDeviceIntake.preferences(from: reading(food: "抹茶のスイーツ", kind: .cafe), text: "抹茶のスイーツが食べたい")
        #expect(sweets.query == "抹茶のスイーツ")
        #expect(sweets.category == nil)
        let cafe = OnDeviceIntake.preferences(from: reading([.rest], kind: .cafe, unhandled: ["静かな"]),
                                              text: "静かなカフェで1時間ゆっくり")
        #expect(cafe.category == "cafe")
        #expect(cafe.query == "カフェ")
        #expect(cafe.restMinutes == 60)
        #expect(cafe.unhandled == ["静かな"])
    }

    @Test func dropsEmptyAndInventedUnhandled() {
        let result = OnDeviceIntake.preferences(from: reading(unhandled: ["", "none", "静かな"]), text: "少し休みたい")
        #expect(result.unhandled.isEmpty)
    }

    @Test func outOfRangeNumbersBecomeUnhandled() {
        let result = OnDeviceIntake.preferences(from: reading([.walk, .rest]), text: "歩くのは2時間まで、30分休憩")
        #expect(result.walkMinutes == nil)
        #expect(result.restMinutes == 30)
        #expect(result.unhandled == ["2時間"])
        #expect(result.isValid)
    }
}
