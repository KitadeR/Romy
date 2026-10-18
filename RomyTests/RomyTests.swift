//
//  RomyTests.swift
//  RomyTests
//
//  Created by 北出琉和 on 2026/10/14.
//

import Foundation
import MapKit
import SwiftData
import Testing
@testable import Romy

private let tokyo: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
    return calendar
}()

private func day(_ year: Int, _ month: Int, _ dayOfMonth: Int) -> Date {
    tokyo.date(from: DateComponents(year: year, month: month, day: dayOfMonth))!
}

/// Part of the 2026–2027 Cabinet Office list, enough for the cases below.
private let holidays = HolidayCalendar(csv: """
国民の祝日・休日月日,国民の祝日・休日名称
2026/9/21,敬老の日
2026/9/22,休日
2026/9/23,秋分の日
2026/10/12,スポーツの日
2026/11/3,文化の日
2026/11/23,勤労感謝の日
2027/1/1,元日
2027/1/11,成人の日
""")

struct HolidayCalendarTests {
    @Test func readsHolidays() {
        #expect(holidays.isHoliday(day(2026, 11, 23), calendar: tokyo))
        #expect(!holidays.isHoliday(day(2026, 11, 22), calendar: tokyo))
        #expect(holidays.isCovered(day(2027, 12, 31), calendar: tokyo))
        #expect(!holidays.isCovered(day(2028, 1, 1), calendar: tokyo))
    }

    @Test func bundledListLoads() {
        let bundled = HolidayCalendar.bundled
        #expect(bundled.isHoliday(day(2026, 11, 3), calendar: tokyo))
        #expect(bundled.isCovered(day(2027, 6, 1), calendar: tokyo))
    }
}

struct QuickDatesTests {
    let quick = QuickDates(calendar: tokyo, holidays: holidays)

    @Test func weekendsFromWednesday() {
        let options = quick.options(today: day(2026, 10, 14))
        #expect(options.map(\.kind) == [.thisWeekend, .nextWeekend, .nextLongWeekend])
        #expect(options[0].start == day(2026, 10, 17) && options[0].end == day(2026, 10, 18))
        #expect(options[1].start == day(2026, 10, 24) && options[1].end == day(2026, 10, 25))
        // 11/3 (Tue) is not a 3-day weekend; 11/21–23 is.
        #expect(options[2].start == day(2026, 11, 21) && options[2].end == day(2026, 11, 23))
    }

    @Test func saturdayIsThisWeekend() {
        let weekend = quick.thisWeekend(today: day(2026, 10, 17))
        #expect(weekend.start == day(2026, 10, 17))
    }

    @Test func sundayMovesToNextWeekend() {
        let weekend = quick.thisWeekend(today: day(2026, 10, 18))
        #expect(weekend.start == day(2026, 10, 24))
    }

    @Test func longRunIsReturnedWhole() throws {
        // 9/19 (Sat) – 9/23 (Wed) is a 5-day run.
        let run = try #require(quick.nextLongWeekend(today: day(2026, 9, 14)))
        #expect(run.start == day(2026, 9, 19) && run.end == day(2026, 9, 23))
    }

    @Test func runAlreadyStartedIsSkipped() throws {
        // 9/21 is inside the 9/19–23 run, so the next one is 10/10–12 (スポーツの日).
        let run = try #require(quick.nextLongWeekend(today: day(2026, 9, 21)))
        #expect(run.start == day(2026, 10, 10) && run.end == day(2026, 10, 12))
    }

    @Test func noAnswerBeyondTheList() {
        #expect(quick.nextLongWeekend(today: day(2027, 12, 20)) == nil)
    }
}

struct DateTextTests {
    let text = DateText(calendar: tokyo, holidays: holidays)

    @Test func labels() {
        #expect(text.shortRange(day(2026, 10, 17), day(2026, 10, 18)) == "10/17（土）〜18（日）")
        #expect(text.shortRange(day(2026, 11, 21), day(2026, 11, 23)) == "11/21（土）〜23（月・祝）")
        #expect(text.range(day(2026, 10, 31), day(2026, 11, 1)) == "10/31（土）〜11/1（日）")
        #expect(text.dayCount(day(2026, 11, 21), day(2026, 11, 23)) == 3)
    }
}

struct TripNamingTests {
    let kyoto = Destination(id: "261009", name: "京都市", context: "京都府", kind: .municipality)
    let osaka = Destination(id: "270008", name: "大阪府", kind: .prefecture)
    let hakone = Destination(id: "143821", name: "箱根町", context: "神奈川県", kind: .municipality)

    @Test func usesFirstTwoDestinations() {
        let name = TripNaming.autoName(
            destinations: [kyoto, osaka, hakone], dates: .undecided, existingNames: [], calendar: tokyo
        )
        #expect(name == "京都・大阪旅行")
    }

    @Test func noDestination() {
        let name = TripNaming.autoName(destinations: [], dates: .undecided, existingNames: [], calendar: tokyo)
        #expect(name == "新しい旅行")
    }

    @Test func duplicateGetsMonthWhenDatesFixed() {
        let fixed = TripDates.range(start: day(2026, 11, 21), end: day(2026, 11, 23))
        let name = TripNaming.autoName(destinations: [kyoto], dates: fixed, existingNames: ["京都旅行"], calendar: tokyo)
        #expect(name == "京都旅行（11月）")
    }

    @Test func duplicateGetsNumberOtherwise() {
        let name = TripNaming.autoName(
            destinations: [kyoto],
            dates: .days(3),
            existingNames: ["京都旅行", "京都旅行 2"],
            calendar: tokyo
        )
        #expect(name == "京都旅行 3")
    }

    @Test func shortNames() {
        #expect(hakone.shortName == "箱根")
        #expect(Destination(id: "010006", name: "北海道", kind: .prefecture).shortName == "北海道")
        #expect(Destination(id: "131016", name: "千代田区", kind: .municipality).shortName == "千代田区")
        #expect(Destination(id: "242012", name: "津市", kind: .municipality).shortName == "津市")
    }
}

struct DestinationCatalogTests {
    let catalog = DestinationCatalog.bundled

    @Test func hasAllPrefectures() {
        #expect(catalog.entries.filter(\.isPrefecture).count == 47)
    }

    @Test func searchesByNameAndReading() {
        let byName = catalog.search("京都").map(\.name)
        #expect(byName.prefix(2) == ["京都府", "京都市"])
        #expect(catalog.search("はこね").map(\.name).contains("箱根町"))
        #expect(catalog.search("ハコネ").map(\.name).contains("箱根町"))
        #expect(catalog.search("  ").isEmpty)
    }

    /// Real completions seen on the Simulator (2026-10-14).
    @Test func areaResultsKeepPlacesOnly() {
        #expect(AreaSearch.isPlace(title: "箱根ケ崎", subtitle: "東京都西多摩郡瑞穂町"))
        #expect(AreaSearch.isPlace(title: "舞浜", subtitle: "千葉県浦安市"))
        #expect(!AreaSearch.isPlace(title: "箱根水明荘湯本702", subtitle: "神奈川県足柄下郡箱根町"))
        #expect(!AreaSearch.isPlace(title: "舞浜アンフィシアター舞浜2-50", subtitle: "千葉県浦安市"))
        #expect(!AreaSearch.isPlace(title: "ディズニー, OK", subtitle: "アメリカ合衆国"))
    }

    @Test func landmarkNameMatch() {
        #expect(AreaSearch.name("東京ディズニーランド", contains: "でぃずにー"))
        #expect(AreaSearch.name("清水寺", contains: "清水寺"))
        #expect(AreaSearch.name("UNIVERSAL STUDIOS JAPAN", contains: "universal"))
        #expect(!AreaSearch.name("東京ドーム", contains: "とうきょう"))
    }

    @Test func townFromAddress() {
        #expect(AreaSearch.town(from: "浦安市舞浜1-1") == "浦安市")
        #expect(AreaSearch.town(from: "〒279-8511, 千葉県浦安市舞浜1-1") == "浦安市")
        #expect(AreaSearch.town(from: "足柄下郡箱根町元箱根139") == "箱根町")
        #expect(AreaSearch.town(from: "箱根町, 足柄下郡") == "箱根町")
        #expect(AreaSearch.area(from: "愛知県大府市, 横根町") == "愛知県大府市")
    }

    @Test func kindLabels() {
        let kyoto = Destination(id: "261009", name: "京都市", context: "京都府", kind: .municipality)
        let tdr = Destination(id: "x", name: "東京ディズニーリゾート", context: "浦安市", kind: .landmark, category: "テーマパーク")
        #expect(Destination(id: "260002", name: "京都府", kind: .prefecture).detail == "都道府県")
        #expect(kyoto.detail == "市・京都府")
        #expect(Destination(id: "y", name: "舞浜", context: "千葉県浦安市", kind: .area).detail == "地域・千葉県浦安市")
        #expect(tdr.detail == "テーマパーク・浦安市")
        #expect(TripNaming.autoName(destinations: [tdr], dates: .undecided, existingNames: [], calendar: tokyo)
            == "東京ディズニーリゾート旅行")
    }
}

struct SightCatalogTests {
    private let catalog: SightCatalog = {
        let json = """
        [
          {"id":"Q1","name":"鹿苑寺","aliases":["金閣寺"],"kana":["ろくおんじ"],"aliasKana":["きんかくじ"],"kind":"寺",
           "town":"北区","prefecture":"京都府","lat":35,"lon":135,"views":900},
          {"id":"Q2","name":"清水寺","aliases":[],"kana":["きよみずでら"],"aliasKana":[],"kind":"寺",
           "town":"東山区","prefecture":"京都府","lat":35,"lon":135,"views":1000},
          {"id":"Q3","name":"東京ディズニーランド","aliases":[],"kana":["とうきょうでぃずにーらんど"],"aliasKana":[],
           "kind":"テーマパーク","town":"浦安市","prefecture":"千葉県","lat":35,"lon":139,"views":2000},
          {"id":"Q4","name":"東京タワー","aliases":[],"kana":["とうきょうたわー"],"aliasKana":[],"kind":"タワー",
           "town":"港区","prefecture":"東京都","lat":35,"lon":139,"views":1500}
        ]
        """
        let entries = (try? JSONDecoder().decode([SightCatalog.Entry].self, from: Data(json.utf8))) ?? []
        return SightCatalog(entries: entries)
    }()

    @Test func fixtureLoads() {
        #expect(catalog.entries.count == 4)
    }

    /// The bundled list (built 2026-10-15). If a yearly rebuild changes the order, check it by eye.
    @Test func bundledListFindsFamousSights() {
        let bundled = SightCatalog.bundled
        #expect(bundled.entries.count > 2000)
        #expect(bundled.search("でぃずにー").first?.name == "東京ディズニーランド")
        #expect(bundled.search("きよみずでら").first?.detail == "寺・京都市")
        #expect(bundled.search("きんかくじ").first?.name == "金閣寺")
        #expect(bundled.search("ちゅらうみ").first?.name == "沖縄美ら海水族館")
        #expect(bundled.search("ひめじ").first?.name == "姫路城")
    }

    @Test func findsByReading() {
        #expect(catalog.search("きよみず").map(\.name) == ["清水寺"])
    }

    @Test func aliasReadingShowsAlias() {
        #expect(catalog.search("きんかくじ").map(\.name) == ["金閣寺"])
    }

    @Test func aliasIsShownWhenTyped() {
        let found = catalog.search("金閣")
        #expect(found.map(\.name) == ["金閣寺"])
        #expect(found.first?.detail == "寺・北区（京都府）")
    }

    @Test func moreViewedFirst() {
        #expect(catalog.search("とうきょう").map(\.name) == ["東京ディズニーランド", "東京タワー"])
        #expect(catalog.search("ディズニー").map(\.name) == ["東京ディズニーランド"])
    }

    @Test func tokyoWardsKeepTheirName() {
        #expect(SightCatalog.place(town: "港区", prefecture: "東京都") == "港区")
        #expect(SightCatalog.place(town: "浦安市", prefecture: "千葉県") == "浦安市")
    }
}

struct TripCreationModelTests {
    @Test func specificDatesNeedADay() {
        let model = TripCreationModel(calendar: tokyo, holidays: holidays, today: day(2026, 10, 14))
        _ = model.advance()
        model.dateMode = .specific
        #expect(!model.canContinue)
        model.tapCalendarDay(day(2026, 11, 1))
        #expect(model.canContinue)
        _ = model.advance()
        #expect(model.dates == .range(start: day(2026, 11, 1), end: day(2026, 11, 1)))
    }

    @Test func calendarTapsMakeARange() {
        let model = TripCreationModel(calendar: tokyo, holidays: holidays, today: day(2026, 10, 14))
        model.tapCalendarDay(day(2026, 11, 21))
        model.tapCalendarDay(day(2026, 11, 23))
        #expect(model.rangeStart == day(2026, 11, 21) && model.rangeEnd == day(2026, 11, 23))
        model.tapCalendarDay(day(2026, 11, 10))
        #expect(model.rangeStart == day(2026, 11, 10) && model.rangeEnd == nil)
    }

    @Test func blankNameIsAuto() {
        let model = TripCreationModel(calendar: tokyo, holidays: holidays, today: day(2026, 10, 14))
        model.toggle(Destination(id: "261009", name: "京都市", context: "京都府", kind: .municipality))
        let trip = model.makeTrip(existingNames: [])
        #expect(trip.name == "京都旅行" && trip.isNameAuto)
        #expect(trip.dates == .undecided)
    }
}

struct NextActionPickerTests {
    private func step(
        _ title: String,
        on dayNumber: Int?,
        hour: Int? = nil,
        order: Int = 0,
        needsDates: Bool = false
    ) -> TrainStep {
        TrainStep(
            route: "新幹線 東京→京都",
            title: title,
            number: 1,
            total: 6,
            day: dayNumber,
            departure: hour.map { day(2026, 11, 9).addingTimeInterval(Double($0) * 3600) },
            addedOrder: order,
            needsTripDates: needsDates
        )
    }

    @Test func withNothingYetItIsAddPlans() {
        #expect(NextActionPicker.pick(dates: .undecided, trainSteps: [], undecidedPlanCount: 0) == .addPlans)
    }

    @Test func undecidedPlansNeedDays() {
        #expect(NextActionPicker
            .pick(dates: .days(3), trainSteps: [], undecidedPlanCount: 2) == .placeUndecided(count: 2))
        #expect(NextActionPicker.pick(dates: .undecided, trainSteps: [], undecidedPlanCount: 2) == .addPlans)
    }

    @Test func nearerDayThenEarlierDepartureThenUndecided() {
        let later = step("帰り", on: 3)
        let morning = step("朝", on: 1, hour: 7)
        let noon = step("昼", on: 1, hour: 12)
        let floating = step("未定", on: nil, order: 0)
        let picked = NextActionPicker.pick(
            dates: .days(3),
            trainSteps: [floating, later, noon, morning],
            undecidedPlanCount: 5
        )
        #expect(picked == .trainStep(morning))
    }

    @Test func bookingWithoutDatesAsksForDates() {
        let booking = step("予約する", on: 1, needsDates: true)
        #expect(NextActionPicker
            .pick(dates: .days(2), trainSteps: [booking], undecidedPlanCount: 0) == .decideDates(for: booking))
        let fixed = TripDates.range(start: day(2026, 11, 9), end: day(2026, 11, 10))
        #expect(NextActionPicker
            .pick(dates: fixed, trainSteps: [booking], undecidedPlanCount: 0) == .trainStep(booking))
    }
}

struct TripCountdownTests {
    let text = DateText(calendar: tokyo, holidays: holidays)

    @Test func eachDateStage() {
        let fixed = TripCountdown(
            dates: .range(start: day(2026, 11, 9), end: day(2026, 11, 11)),
            today: day(2026, 10, 28),
            text: text
        )
        #expect([fixed.lead, fixed.value, fixed.trail] == ["あと", "12", "日で出発"])
        #expect(fixed.caption == "11/9〜11/11 ・ 3日間")
        #expect(fixed.short == "あと12日")
        #expect(!fixed.offersDateDecision)

        let days = TripCountdown(dates: .days(3), today: day(2026, 10, 28), text: text)
        #expect([days.lead, days.value, days.trail] == ["この旅は", "3", "日間"])
        #expect(days.caption == "3日間 ・ 日付未定" && days.offersDateDecision)

        let open = TripCountdown(dates: .undecided, today: day(2026, 10, 28), text: text)
        #expect([open.lead, open.value] == ["いつ行くか", "未定"] && open.caption == "日付未定")
    }

    @Test func departureDayAndDuringTheTrip() {
        let range = TripDates.range(start: day(2026, 11, 9), end: day(2026, 11, 11))
        #expect(TripCountdown(dates: range, today: day(2026, 11, 9), text: text).value == "今日")
        #expect(TripCountdown(dates: range, today: day(2026, 11, 10), text: text).value == "旅行中")
    }
}

struct ItineraryDaysTests {
    let text = DateText(calendar: tokyo, holidays: holidays)

    @Test func daysAndTabLabels() {
        let fixed = ItineraryDays(dates: .range(start: day(2026, 11, 9), end: day(2026, 11, 11)), text: text)
        #expect(fixed.days.map(\.number) == [1, 2, 3])
        #expect(fixed.days.map { fixed.tabLabel($0) } == ["11/9 1日目", "11/10 2日目", "11/11 3日目"])

        let counted = ItineraryDays(dates: .days(2), text: text)
        #expect(counted.days.map { counted.tabLabel($0) } == ["1日目", "2日目"])
        #expect(ItineraryDays(dates: .undecided, text: text).days.isEmpty)
    }

    @Test func captionsFollowFigma16() {
        let fixed = ItineraryDays(dates: .range(start: day(2026, 11, 9), end: day(2026, 11, 11)), text: text)
        #expect(fixed.caption(for: .all, hasDestination: true) == "11/9（月）〜11/11（水） ・ 3日間")
        #expect(fixed.caption(for: .day(1), hasDestination: true) == "1日目 ・ 11/9（月）")
        #expect(fixed.caption(for: .undecided, hasDestination: true) == "日がまだ決まっていない予定")

        let counted = ItineraryDays(dates: .days(3), text: text)
        #expect(counted.caption(for: .all, hasDestination: true) == "3日間 ・ 日付未定")
        #expect(counted.caption(for: .day(2), hasDestination: true) == "2日目")

        let open = ItineraryDays(dates: .undecided, text: text)
        #expect(open.caption(for: .all, hasDestination: true) == "いつ行くか 未定")
        #expect(open.caption(for: .undecided, hasDestination: false) == "行き先 未定 ・ いつ行くか 未定")
    }

    @Test func placementAndNewPlanDay() {
        #expect(ItineraryDays.placement(of: 2, dayCount: 3) == 2)
        #expect(ItineraryDays.placement(of: 4, dayCount: 3) == nil)
        #expect(ItineraryDays.placement(of: nil, dayCount: 3) == nil)
        #expect(ItineraryTab.day(2).dayForNewPlan == 2)
        #expect(ItineraryTab.all.dayForNewPlan == nil && ItineraryTab.undecided.dayForNewPlan == nil)
        #expect(ItineraryDays.addedMessage(title: "伏見稲荷大社", day: 1) == "伏見稲荷大社を1日目に追加しました")
        #expect(ItineraryDays.addedMessage(title: "清水寺", day: nil) == "清水寺を未定に追加しました")
    }
}

struct PlaceSearchTests {
    @Test func wardFromPlacemark() {
        #expect(PlaceSearch.ward(locality: "京都市", subLocality: "東山区") == "京都市東山区")
        #expect(PlaceSearch.ward(locality: "港区", subLocality: "六本木") == "港区")
        #expect(PlaceSearch.ward(locality: "箱根町", subLocality: "湯本") == "箱根町")
        #expect(PlaceSearch.ward(locality: nil, subLocality: "東山区") == nil)
    }

    @Test func regionAroundDestinations() {
        #expect(PlaceSearch.region(around: []) == nil)
        let kyoto = CLLocationCoordinate2D(latitude: 35.0, longitude: 135.77)
        let osaka = CLLocationCoordinate2D(latitude: 34.69, longitude: 135.50)
        let region = try! #require(PlaceSearch.region(around: [kyoto, osaka]))
        #expect(abs(region.center.latitude - 34.845) < 0.001)
        #expect(region.span.latitudeDelta >= 0.4)
    }
}

@MainActor
struct TripItemsTests {
    private func makeTrip(_ dates: TripDates) throws -> (ModelContext, Trip) {
        let container = try ModelContainer(
            for: Trip.self, ItineraryItem.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        let trip = Trip(name: "京都旅行", isNameAuto: true, destinations: [], dates: dates)
        context.insert(trip)
        return (context, trip)
    }

    private func add(_ title: String, day: Int?, to trip: Trip, in context: ModelContext) {
        let item = ItineraryItem(title: title, day: day, order: trip.nextOrder(on: day), kind: .nameOnly)
        context.insert(item)
        item.trip = trip
    }

    @Test func itemsKeepTheirOrderPerDay() throws {
        let (context, trip) = try makeTrip(.days(2))
        add("伏見稲荷大社", day: 1, to: trip, in: context)
        add("錦市場", day: 1, to: trip, in: context)
        add("嵐山", day: 2, to: trip, in: context)
        add("抹茶のお店", day: nil, to: trip, in: context)
        #expect(trip.items(on: 1).map(\.title) == ["伏見稲荷大社", "錦市場"])
        #expect(trip.items(on: 2).map(\.title) == ["嵐山"])
        #expect(trip.items(on: nil).map(\.title) == ["抹茶のお店"])
    }

    @Test func plansStayOnTheirDayWhenDatesAreDecided() throws {
        let (context, trip) = try makeTrip(.days(3))
        add("清水寺", day: 2, to: trip, in: context)
        trip.dates = .range(start: .now, end: Calendar.current.date(byAdding: .day, value: 2, to: .now)!)
        trip.moveItemsPastLastDay()
        #expect(trip.items(on: 2).map(\.title) == ["清水寺"])
    }

    @Test func movingGoesToTheEndOfTheOtherDay() throws {
        let (context, trip) = try makeTrip(.days(2))
        add("A", day: 1, to: trip, in: context)
        add("B", day: 1, to: trip, in: context)
        add("C", day: 2, to: trip, in: context)
        let a = try #require(trip.items.first { $0.title == "A" })
        trip.move(a, toDay: 2)
        #expect(trip.items(on: 1).map(\.title) == ["B"])
        #expect(trip.items(on: 2).map(\.title) == ["C", "A"])
        trip.move(a, toDay: nil)
        #expect(trip.items(on: nil).map(\.title) == ["A"])
        #expect(trip.items(on: 2).map(\.title) == ["C"])
    }

    @Test func droppingOnAPlanTakesItsPlace() throws {
        let (context, trip) = try makeTrip(.days(2))
        for title in ["A", "B", "C"] { add(title, day: 1, to: trip, in: context) }
        add("D", day: 2, to: trip, in: context)
        let (a, c, d) = (
            try #require(trip.items.first { $0.title == "A" }),
            try #require(trip.items.first { $0.title == "C" }),
            try #require(trip.items.first { $0.title == "D" })
        )
        trip.reorder(a, onto: c)
        #expect(trip.items(on: 1).map(\.title) == ["B", "C", "A"])
        trip.reorder(d, onto: trip.items(on: 1)[0])
        #expect(trip.items(on: 1).first?.title == "D")
        #expect(trip.items(on: 2).isEmpty)
        #expect(trip.items(on: 1).map(\.order) == [0, 1, 2, 3])
    }

    @Test func plansPastTheLastDayMoveToUndecided() throws {
        let (context, trip) = try makeTrip(.days(3))
        add("抹茶のお店", day: nil, to: trip, in: context)
        add("嵐山", day: 3, to: trip, in: context)
        trip.dates = .range(start: .now, end: Calendar.current.date(byAdding: .day, value: 1, to: .now)!)
        trip.moveItemsPastLastDay()
        #expect(trip.items(on: nil).map(\.title) == ["抹茶のお店", "嵐山"])
        #expect(trip.items.first { $0.title == "嵐山" }?.day == nil)
    }
}

struct PlaceSearchTownTests {
    @Test func townOnlyWhenItIsATown() {
        #expect(PlaceSearch.town(from: "〒089-0100, 北海道上川郡清水町") == "清水町")
        #expect(PlaceSearch.town(from: "京都府京都市東山区清水1丁目294") == "京都市")
        #expect(PlaceSearch.town(from: "きよみず公園") == nil)
        #expect(PlaceSearch.town(from: "〒066-0041") == nil)
    }
}

@MainActor
struct ItineraryPinsTests {
    @Test func daysShownPerTab() {
        #expect(ItineraryPins.days(for: .all, dayCount: 3) == [1, 2, 3])
        #expect(ItineraryPins.days(for: .day(2), dayCount: 3) == [2])
        #expect(ItineraryPins.days(for: .undecided, dayCount: 3).isEmpty)
        #expect(ItineraryPins.days(for: .all, dayCount: 0).isEmpty)
    }

    @Test func pinsKeepTheCardNumber() {
        let items = [
            ItineraryItem(title: "伏見稲荷大社", day: 1, order: 0, kind: .sight, latitude: 34.967, longitude: 135.772),
            ItineraryItem(title: "さんぽ", day: 1, order: 1, kind: .nameOnly),
            ItineraryItem(title: "錦市場", day: 1, order: 2, kind: .food, latitude: 35.005, longitude: 135.764)
        ]
        let pins = ItineraryPins.pins(day: 1, items: items)
        #expect(pins.map(\.number) == [1, 3])
        #expect(pins.allSatisfy { $0.day == 1 })
    }

    @Test func areaAroundPins() throws {
        #expect(ItineraryPins.rect(around: []) == nil)
        let one = try #require(ItineraryPins.rect(around: [CLLocationCoordinate2D(latitude: 35, longitude: 135.77)]))
        #expect(one.width > 0 && one.height > 0)
        let kyoto = CLLocationCoordinate2D(latitude: 35.0, longitude: 135.77)
        let osaka = CLLocationCoordinate2D(latitude: 34.69, longitude: 135.50)
        let both = try #require(ItineraryPins.rect(around: [kyoto, osaka]))
        #expect(both.contains(MKMapPoint(kyoto)) && both.contains(MKMapPoint(osaka)))
    }

    @Test func targetSitsInTheOpenTopPart() {
        let target = MKMapRect(x: 1000, y: 1000, width: 100, height: 100)
        let shown = ItineraryPins.rect(showing: target, visibleFraction: 0.4, aspect: 0.5)
        let open = MKMapRect(x: shown.minX, y: shown.minY, width: shown.width, height: shown.height * 0.4)
        #expect(open.contains(MKMapPoint(x: target.minX, y: target.minY)))
        #expect(open.contains(MKMapPoint(x: target.maxX - 0.001, y: target.maxY - 0.001)))
        #expect(abs(open.midY - target.midY) < 0.001 && abs(shown.midX - target.midX) < 0.001)
        #expect(abs(shown.width / shown.height - 0.5) < 0.0001)
    }
}

struct DayScheduleTests {
    private func plan(_ duration: Int, fixed: Int? = nil) -> DaySchedule.Input {
        DaySchedule.Input(id: UUID(), durationMinutes: duration, fixedStartMinutes: fixed)
    }

    @Test func guessedTimesFollowOneAnother() {
        let plans = [plan(60), plan(90), plan(30)]
        let schedule = DaySchedule(dayStartMinutes: 9 * 60, plans: plans)
        #expect(schedule.slots.map(\.startMinutes) == [540, 600, 690])
        #expect(schedule.slots.map(\.endMinutes) == [600, 690, 720])
        #expect(schedule.slots.allSatisfy { !$0.isFixed })
    }

    @Test func fixedStartHoldsAndLaterPlansFollowIt() {
        let plans = [plan(60), plan(60, fixed: 12 * 60 + 30), plan(60)]
        let schedule = DaySchedule(dayStartMinutes: 9 * 60, plans: plans)
        #expect(schedule.slots.map(\.startMinutes) == [540, 750, 810])
        #expect(schedule.slots.map(\.isFixed) == [false, true, false])
    }

    @Test func clockPastMidnightKeepsCounting() {
        #expect(DaySchedule.clock(540) == "9:00")
        #expect(DaySchedule.clock(25 * 60 + 5) == "25:05")
    }
}

struct DayProgressTests {
    private func plans(_ done: [Bool]) -> [DayProgress.Input] {
        done.map { DayProgress.Input(id: UUID(), isDone: $0) }
    }

    private func states(_ inputs: [DayProgress.Input], isToday: Bool = true) -> [DayProgress.State] {
        let progress = DayProgress(plans: inputs, isToday: isToday)
        return inputs.map { progress.state(of: $0.id) }
    }

    @Test func firstPlanIsNowWhenNothingIsDone() {
        #expect(states(plans([false, false, false])) == [.now, .upcoming, .upcoming])
    }

    @Test func nowIsTheNextAfterTheLastDone() {
        #expect(states(plans([true, true, false, false])) == [.done, .done, .now, .upcoming])
    }

    @Test func notDoneBeforeTheLastDoneIsSkipped() {
        #expect(states(plans([true, false, true, false])) == [.done, .skipped, .done, .now])
    }

    @Test func unmarkingAnEarlierPlanSkipsItAndNowStays() {
        // Everything but the last plan was done; the first is un-marked.
        #expect(states(plans([false, true, true, false])) == [.skipped, .done, .done, .now])
    }

    @Test func unmarkingTheLastDoneMakesItNowAgain() {
        #expect(states(plans([true, true, false])) == [.done, .done, .now])
        #expect(states(plans([true, false, false])) == [.done, .now, .upcoming])
    }

    @Test func nothingIsNowWhenEverythingIsDone() {
        #expect(states(plans([true, true])) == [.done, .done])
    }

    @Test func otherDaysKeepDoneMarksButHaveNoNowOrSkip() {
        #expect(states(plans([true, false, true, false]), isToday: false) == [.done, .upcoming, .done, .upcoming])
    }

    @Test func emptyDayHasNoStates() {
        #expect(states([]).isEmpty)
    }
}

struct TripPhaseTests {
    private let dates = TripDates.range(start: day(2026, 11, 9), end: day(2026, 11, 11))

    private func phase(_ dates: TripDates, on today: Date) -> TripPhase {
        TripPhase(dates: dates, today: today, calendar: tokyo)
    }

    @Test func planUntilTwoDaysBefore() {
        #expect(phase(dates, on: day(2026, 11, 7)) == .plan)
    }

    @Test func actionStartsTheDayBefore() {
        #expect(phase(dates, on: day(2026, 11, 8)) == .action)
        #expect(phase(dates, on: day(2026, 11, 9)) == .action)
        #expect(phase(dates, on: day(2026, 11, 11)) == .action)
    }

    @Test func memoriesAfterTheLastDay() {
        #expect(phase(dates, on: day(2026, 11, 12)) == .memories)
    }

    @Test func tripsWithoutFixedDatesStayInPlan() {
        #expect(phase(.undecided, on: day(2026, 11, 9)) == .plan)
        #expect(phase(.days(3), on: day(2026, 11, 9)) == .plan)
    }

    @Test func dayNumberFollowsTheDates() {
        #expect(dates.dayNumber(on: day(2026, 11, 8), calendar: tokyo) == nil)
        #expect(dates.dayNumber(on: day(2026, 11, 9), calendar: tokyo) == 1)
        #expect(dates.dayNumber(on: day(2026, 11, 11), calendar: tokyo) == 3)
        #expect(dates.dayNumber(on: day(2026, 11, 12), calendar: tokyo) == nil)
        #expect(TripDates.days(3).dayNumber(on: day(2026, 11, 9), calendar: tokyo) == nil)
    }
}

struct PlaceSearchSuggestionTests {
    private func place(
        _ name: String, category: MKPointOfInterestCategory? = nil, lat: Double = 35.68
    ) -> PlaceSearch.Result {
        let item = MKMapItem(location: CLLocation(latitude: lat, longitude: 139.76), address: nil)
        item.name = name
        item.pointOfInterestCategory = category
        return PlaceSearch.result(from: item)!
    }

    private func suggestion(_ title: String, town: String? = "千代田区") -> PlaceSearch.Result {
        PlaceSearch.Result(
            id: "suggestion:\(title)", title: title, category: "場所", kind: .other,
            town: town, item: nil, completion: nil
        )
    }

    @Test func suggestionsComeFirstThenTheFoundPlaces() {
        let merged = PlaceSearch.merge(
            suggestions: [suggestion("東京駅"), suggestion("東京タワー", town: "港区")],
            found: [place("東京都")]
        )
        #expect(merged.map(\.title) == ["東京駅", "東京タワー", "東京都"])
        #expect(merged.map { $0.item == nil } == [true, true, false])
    }

    @Test func aFoundPlaceTakesTheSpotOfItsSuggestion() {
        let tower = place("東京タワー", category: .landmark)
        let merged = PlaceSearch.merge(
            suggestions: [suggestion("東京駅"), suggestion("東京タワー", town: "港区")],
            found: [tower]
        )
        #expect(merged.map(\.title) == ["東京駅", "東京タワー"])
        #expect(merged[1].id == tower.id)
        #expect(merged[1].item != nil)
        #expect(merged[1].category == "名所")
    }

    @Test func theSameSuggestionIsShownOnce() {
        let merged = PlaceSearch.merge(suggestions: [suggestion("東京駅"), suggestion("東京駅")], found: [])
        #expect(merged.count == 1)
    }

    @Test func mergeKeepsAtMostTheLimit() {
        let suggestions = (0..<12).map { suggestion("場所\($0)", town: "区\($0)") }
        let found = (0..<12).map { place("店\($0)", lat: 35 + Double($0) / 10) }
        #expect(PlaceSearch.merge(suggestions: suggestions, found: found, limit: 15).count == 15)
    }

    @Test func areaCenterIsTheAreaNotAPlace() throws {
        let area = place("東京都", lat: 35.69)
        let station = place("東京駅", category: .landmark, lat: 35.68)
        let center = try #require(PlaceSearch.areaCenter(in: [station, area], matching: "東京"))
        #expect(abs(center.latitude - 35.69) < 0.0001)
        #expect(PlaceSearch.areaCenter(in: [station], matching: "東京") == nil)
        #expect(PlaceSearch.areaCenter(in: [area], matching: "大阪") == nil)
    }

    @Test func areaRegionIsCenteredOnTheArea() {
        let region = PlaceSearch.areaRegion(around: CLLocationCoordinate2D(latitude: 35.69, longitude: 139.69))
        #expect(region.center.latitude == 35.69)
        #expect(region.span.latitudeDelta == 0.5)
    }

    @Test func suggestionDetailShowsItsTown() {
        #expect(suggestion("東京駅").detail == "場所 ・ 千代田区")
        #expect(suggestion("東京駅", town: nil).detail == "場所")
    }
}

struct AreaSearchOrderTests {
    private func sight(_ title: String) -> AreaSearch.Result {
        AreaSearch.Result(title: title, detail: "", kind: .landmark, completion: nil, item: nil)
    }

    @Test func nameMatchesComeBeforeLooseOnes() {
        let sights = ["東京ディズニーシー", "東京ドイツ村", "東京ドームシティ", "東京サマーランド", "東京ジョイポリス", "東京駅"]
            .map(sight)
        let ordered = AreaSearch.nameMatchesFirst(sights, query: "東京駅")
        #expect(ordered.map(\.title) == ["東京駅", "東京ディズニーシー", "東京ドイツ村", "東京ドームシティ", "東京サマーランド"])
    }

    @Test func orderIsKeptWithinEachGroup() {
        let sights = ["B公園", "Aランド", "Cランド", "Dパーク"].map(sight)
        let ordered = AreaSearch.nameMatchesFirst(sights, query: "ランド")
        #expect(ordered.map(\.title) == ["Aランド", "Cランド", "B公園", "Dパーク"])
    }

    @Test func kanaAndWidthAreIgnoredWhenMatching() {
        let sights = ["東京ドーム", "東京ディズニーランド"].map(sight)
        #expect(AreaSearch.nameMatchesFirst(sights, query: "でぃずにー").map(\.title)
            == ["東京ディズニーランド", "東京ドーム"])
    }

    @Test func atMostTheLimitIsKept() {
        let sights = (0..<10).map { sight("場所\($0)") }
        #expect(AreaSearch.nameMatchesFirst(sights, query: "場所").count == 5)
        #expect(AreaSearch.nameMatchesFirst([], query: "東京").isEmpty)
    }
}
