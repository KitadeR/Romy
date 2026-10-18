import Foundation
import MapKit
import SwiftUI

/// How the person goes from one plan to the next (Notion 02 §6-5 ②移動の行: 徒歩・車・電車, chosen on the row).
enum TravelMode: String, CaseIterable {
    case walking, driving, transit

    var label: String {
        switch self {
        case .walking: "徒歩"
        case .driving: "車"
        case .transit: "電車"
        }
    }

    var symbol: String {
        switch self {
        case .walking: "figure.walk"
        case .driving: "car"
        case .transit: "tram"
        }
    }

    var transportType: MKDirectionsTransportType {
        switch self {
        case .walking: .walking
        case .driving: .automobile
        case .transit: .transit
        }
    }

    /// The color of the mode's icon (Rhyme: walking orange, car blue, train pink).
    var tint: Color {
        switch self {
        case .walking: Color(hex: 0xFE9000)
        case .driving: Color(hex: 0x0097FF)
        case .transit: Color(hex: 0xE5338B)
        }
    }

    /// The mode Apple Maps opens its route with.
    var launchMode: String {
        switch self {
        case .walking: MKLaunchOptionsDirectionsModeWalking
        case .driving: MKLaunchOptionsDirectionsModeDriving
        case .transit: MKLaunchOptionsDirectionsModeTransit
        }
    }

    /// Up to this far in a straight line the first guess is walking, farther the train.
    static let walkingLimitMeters = 1500.0

    static func defaultMode(straightMeters: Double) -> TravelMode {
        straightMeters <= walkingLimitMeters ? .walking : .transit
    }
}

/// The time and distance MapKit gives for one move.
struct TravelEstimate: Equatable {
    let minutes: Int
    let meters: Int

    init(minutes: Int, meters: Int) {
        self.minutes = minutes
        self.meters = meters
    }

    init(seconds: TimeInterval, meters: Double) {
        self.init(minutes: max(1, Int((seconds / 60).rounded())), meters: Int(meters.rounded()))
    }

    /// Apple sometimes answers a short train move with a route far shorter than the straight line
    /// (東京駅→丸ビル: 48 m), which is not a real route. Such a result is not used.
    func isPlausible(straightMeters: Double) -> Bool {
        Double(meters) >= straightMeters * 0.5
    }

    /// 「12分」「1時間」「1時間5分」.
    var durationText: String {
        guard minutes >= 60 else { return "\(minutes)分" }
        return minutes % 60 == 0 ? "\(minutes / 60)時間" : "\(minutes / 60)時間\(minutes % 60)分"
    }

    /// 「900m」「3.4km」.
    var distanceText: String {
        meters < 1000 ? "\(meters)m" : String(format: "%.1fkm", Double(meters) / 1000)
    }
}
