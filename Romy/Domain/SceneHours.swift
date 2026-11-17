import Foundation

/// 店舗の対象日の公開案内。到着・出発の可否は端末の計算で判定する。
struct SceneHours: Codable, Equatable {
    struct Window: Codable, Equatable {
        let start: Int
        let end: Int
        let lastOrder: Int?
    }
    struct Source: Codable, Equatable {
        let url: String
        let title: String?
        let official: Bool
    }
    let status: String
    let date: String
    let timeZone: String
    let windows: [Window]
    let closed: Bool
    let sources: [Source]
    let checkedAt: String

    /// 同じ現地日付・タイムゾーンで、1時間以内の結果だけを判定に使う。
    func isFresh(on target: Date, at now: Date) -> Bool {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        guard timeZone == TimeZone.current.identifier, date == formatter.string(from: target),
              let checked = ISO8601DateFormatter().date(from: checkedAt)
                ?? Self.fractionalFormatter.date(from: checkedAt),
              (0...(status == "official" ? 3600 : 300)).contains(now.timeIntervalSince(checked)) else { return false }
        if status == "official" {
            guard sources.contains(where: { $0.official && URL(string: $0.url)?.scheme == "https" }),
                  closed ? windows.isEmpty : !windows.isEmpty else { return false }
            return windows.allSatisfy { window in
                window.start >= 0 && window.start < window.end && window.end <= 2880
                    && (window.lastOrder.map { (window.start...window.end).contains($0) } ?? true)
            }
        }
        return status == "unknown"
    }

    private static var fractionalFormatter: ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }

    func permits(_ step: SceneStep) -> Bool {
        guard status == "official" else { return true }
        guard !closed else { return false }
        return windows.contains { window in
            step.startMinutes >= window.start && step.leaveMinutes <= window.end
                && step.startMinutes <= (window.lastOrder ?? window.end)
        }
    }

    func caption(for step: SceneStep) -> String {
        guard status == "official" else { return "公式の営業時間を確認できませんでした" }
        if closed { return "公式案内ではこの日は休業です" }
        if !permits(step) { return "到着・滞在予定が営業時間に収まりません" }
        let end = windows.first { $0.start <= step.startMinutes && $0.end >= step.leaveMinutes }?.end ?? 0
        return "公式案内では\(DaySchedule.clock(end))まで"
    }
}
