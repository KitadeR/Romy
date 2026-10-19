import Foundation

/// How a length of time is written: 「12分」「1時間」「1時間5分」.
enum DurationText {
    static func text(minutes: Int) -> String {
        guard minutes >= 60 else { return "\(minutes)分" }
        return minutes % 60 == 0 ? "\(minutes / 60)時間" : "\(minutes / 60)時間\(minutes % 60)分"
    }
}
