import Foundation

/// The big line on the Plan Home for each date stage (Notion 02 §6-3 「日付の段階ごと」):
/// fixed → 「あと 12 日で出発」, day count → 「この旅は 3 日間」, undecided → 「いつ行くか 未定」.
struct TripCountdown: Equatable {
    let lead: String
    let value: String
    let trail: String
    /// Day count and undecided trips offer 「日付を決める」.
    let offersDateDecision: Bool
    /// The small line above the trip name: 「11/9〜11/11 ・ 3日間」「3日間 ・ 日付未定」「日付未定」.
    let caption: String

    init(dates: TripDates, today: Date, text: DateText) {
        let calendar = text.calendar
        switch dates {
        case .undecided:
            (lead, value, trail, offersDateDecision) = ("いつ行くか", "未定", "", true)
            caption = "日付未定"
        case .days(let count):
            (lead, value, trail, offersDateDecision) = ("この旅は", "\(count)", "日間", true)
            caption = "\(count)日間 ・ 日付未定"
        case .range(let start, let end):
            offersDateDecision = false
            caption = "\(text.plainRange(start, end)) ・ \(text.dayCount(start, end))日間"
            let first = calendar.startOfDay(for: today)
            let daysLeft = calendar.dateComponents([.day], from: first, to: calendar.startOfDay(for: start)).day ?? 0
            if daysLeft > 0 {
                (lead, value, trail) = ("あと", "\(daysLeft)", "日で出発")
            } else if daysLeft == 0 {
                (lead, value, trail) = ("", "今日", "出発")
            } else if first <= calendar.startOfDay(for: end) {
                (lead, value, trail) = ("", "旅行中", "")
            } else {
                (lead, value, trail) = ("", "おかえり", "")
            }
        }
    }

    /// Short form for the header shown after scrolling: 「あと12日」.
    var short: String {
        lead == "あと" ? "あと\(value)日" : "\(lead)\(value)\(trail)"
    }
}
