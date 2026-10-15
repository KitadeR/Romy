//
//  RomyTests.swift
//  RomyTests
//
//  Created by 北出琉和 on 2026/10/14.
//

import Foundation
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
        let name = TripNaming.autoName(destinations: [kyoto], dates: .days(3),
                                       existingNames: ["京都旅行", "京都旅行 2"], calendar: tokyo)
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
