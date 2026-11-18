import Foundation

/// A reproducible clock only when an explicit Debug capture launch argument is present.
enum RomyClock {
    static func timelineDate(_ date: Date) -> Date {
        #if DEBUG
        if ScreenshotScene.screen != nil {
            return ScreenshotScene.now
        }
        #endif
        return date
    }

    static var now: Date {
        #if DEBUG
        if ScreenshotScene.screen != nil {
            return ScreenshotScene.now
        }
        #endif
        return .now
    }
}
