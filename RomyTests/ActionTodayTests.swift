import Foundation
import Testing
@testable import Romy

/// What the Action Home shows about today (Figma 71:288, 26-01).
@MainActor
struct ActionTodayTests {
    private func schedule(_ plans: [ItineraryItem]) -> DaySchedule {
        DaySchedule(dayStartMinutes: 13 * 60, plans: plans.map {
            DaySchedule.Input(
                id: $0.id, durationMinutes: 60, fixedStartMinutes: $0.fixedStartMinutes,
                notBeforeMinutes: $0.notBeforeMinutes
            )
        })
    }

    private var scene: [ItineraryItem] {
        let temple = ItineraryItem(title: "東本願寺", day: 2, order: 0, kind: .sight)
        let hotel = ItineraryItem(title: "ホテル", day: 2, order: 1, kind: .stay)
        hotel.notBeforeMinutes = 15 * 60
        let dinner = ItineraryItem(title: "お店", day: 2, order: 2, kind: .food)
        dinner.fixedStartMinutes = 17 * 60
        return [temple, hotel, dinner]
    }

    @Test func theFirstPlanNotDoneIsNowAndTheRestFollow() {
        let plans = scene
        let today = ActionToday(plans: plans, day: 2, schedule: schedule(plans))
        #expect(today.now?.item.title == "東本願寺")
        #expect(today.now?.slot.startMinutes == 13 * 60)
        #expect(today.remaining.map(\.item.title) == ["ホテル", "お店"])
        #expect(today.remaining.map(\.slot.startMinutes) == [15 * 60, 17 * 60])
        #expect(today.stay?.title == "ホテル")
    }

    @Test func aPlanMarkedDoneMovesNowOnAndLeavesTheRest() {
        let plans = scene
        plans[0].doneAt = .now
        let today = ActionToday(plans: plans, day: 2, schedule: schedule(plans))
        #expect(today.now?.item.title == "ホテル")
        #expect(today.remaining.map(\.item.title) == ["お店"])
        #expect(today.stay?.title == "ホテル")
    }

    @Test func aDayWithEverythingDoneHasNoNow() {
        let plans = scene
        for plan in plans { plan.doneAt = .now }
        let today = ActionToday(plans: plans, day: 2, schedule: schedule(plans))
        #expect(today.now == nil)
        #expect(today.remaining.isEmpty)
    }

    @Test func theBigNameIsTheWard() {
        #expect(ActionToday.shortArea("京都市東山区") == "東山区")
        #expect(ActionToday.shortArea("港区") == "港区")
        #expect(ActionToday.shortArea("神戸市") == "神戸市")
        #expect(ActionToday.shortArea("音更町") == "音更町")
    }

    @Test func aStayThatOpensLaterSaysCheckIn() {
        let plans = scene
        #expect(ActionHomeSheet.line(for: plans[1]) == "ホテル ・ チェックイン")
        #expect(ActionHomeSheet.line(for: plans[2]) == "お店")
    }
}
