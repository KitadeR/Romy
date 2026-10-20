import Foundation

/// The time the app goes by. In debug builds it can be set to another moment with the environment variable
/// ROMY_FAKE_NOW (for example 2026-10-31T11:50:00+09:00): the clock starts there and then runs on, so a trip's
/// day can be shown in progress (poster screenshots). Release builds always use the real time.
enum AppClock {
    static var now: Date {
        #if DEBUG
        return .now.addingTimeInterval(offset)
        #else
        return .now
        #endif
    }

    #if DEBUG
    private static let offset: TimeInterval = {
        guard let text = ProcessInfo.processInfo.environment["ROMY_FAKE_NOW"],
              let fake = ISO8601DateFormatter().date(from: text) else { return 0 }
        return fake.timeIntervalSince(.now)
    }()
    #endif
}
