import Foundation

/// Japanese national holidays from the Cabinet Office list (syukujitsu.csv, Shift_JIS).
/// The file covers up to the end of next year; replace it once a year.
/// Source: https://www8.cao.go.jp/chosei/shukujitsu/gaiyou.html
struct HolidayCalendar {
    /// Days as yyyymmdd numbers.
    private let days: Set<Int>
    /// Last day the list covers. Days after it are unknown, not "no holiday".
    private let lastCoveredKey: Int?

    init(csv: String) {
        var days = Set<Int>()
        for line in csv.split(whereSeparator: \.isNewline).dropFirst() {
            let parts = line.split(separator: ",").first?.split(separator: "/") ?? []
            guard parts.count == 3,
                  let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]) else { continue }
            days.insert(year * 10_000 + month * 100 + day)
        }
        self.days = days
        self.lastCoveredKey = days.max().map { ($0 / 10_000) * 10_000 + 1231 }
    }

    static let bundled: HolidayCalendar = {
        guard let url = Bundle.main.url(forResource: "syukujitsu", withExtension: "csv"),
              let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .shiftJIS) else {
            return HolidayCalendar(csv: "")
        }
        return HolidayCalendar(csv: text)
    }()

    func isHoliday(_ date: Date, calendar: Calendar) -> Bool {
        days.contains(Self.key(date, calendar))
    }

    func isCovered(_ date: Date, calendar: Calendar) -> Bool {
        guard let lastCoveredKey else { return false }
        return Self.key(date, calendar) <= lastCoveredKey
    }

    private static func key(_ date: Date, _ calendar: Calendar) -> Int {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return (parts.year ?? 0) * 10_000 + (parts.month ?? 0) * 100 + (parts.day ?? 0)
    }
}
