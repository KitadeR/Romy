import Foundation
import MapKit
import SwiftData

/// Asks Romy's relay (`server/relay`) whether a stay keeps luggage before check-in (Notion 02 §6-4 事実の確認⑤).
/// Only the stay's name and address go out, never where the person is or the itinerary (Notion 04
/// 「2026-10-29｜各社のデータの扱い」①). Nil when nothing came back: offline, the caps, or no relay in this build.
nonisolated struct FactRelay {
    /// The relay on this Mac while it is built (`wrangler dev`); stage 3 puts the deployed one here.
    static let shared = FactRelay(baseURL: {
        #if DEBUG
        URL(string: "http://localhost:8787")
        #else
        nil
        #endif
    }())

    let baseURL: URL?
    var session: URLSession = .shared

    func luggage(title: String, placeID: String?, area: String?) async -> LuggageFact? {
        guard let baseURL else { return nil }
        let address = await Self.address(placeID: placeID) ?? area
        var place: [String: String] = ["name": title]
        place["id"] = placeID
        place["address"] = address
        var request = URLRequest(url: baseURL.appending(path: "v1/check"))
        request.httpMethod = "POST"
        request.timeoutInterval = 70
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(Self.deviceID, forHTTPHeaderField: "X-Romy-Device")
        let body: [String: Any] = ["kind": "luggage_before_checkin", "place": place]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        guard let (data, response) = try? await session.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        guard var fact = Self.decode(data) else { return nil }
        fact.placeKey = LuggageFact.placeKey(title: title, placeID: placeID, area: area)
        return fact
    }

    /// A result to keep. One with a reason (the caps, a failed search) is not kept, so it is asked again.
    static func decode(_ data: Data) -> LuggageFact? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              object["reason"] == nil || object["reason"] is NSNull else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let text = try decoder.singleValueContainer().decode(String.self)
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            guard let date = formatter.date(from: text) ?? ISO8601DateFormatter().date(from: text) else {
                throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: text))
            }
            return date
        }
        return try? decoder.decode(LuggageFact.self, from: data)
    }

    /// The full address from Apple, on this phone, so the relay can tell one branch from another.
    private static func address(placeID: String?) async -> String? {
        guard let placeID, let identifier = MKMapItem.Identifier(rawValue: placeID) else { return nil }
        let item = try? await MKMapItemRequest(mapItemIdentifier: identifier).mapItem
        return item?.address?.fullAddress
    }

    /// An ID for the relay's daily cap only, not tied to the person; stage 3 uses the App Attest key instead.
    private static var deviceID: String {
        let key = "factRelayDeviceID"
        if let id = UserDefaults.standard.string(forKey: key) { return id }
        let id = UUID().uuidString
        UserDefaults.standard.set(id, forKey: key)
        return id
    }
}

/// Whether the person said Romy may check stays (the sheet after adding one, Figma 23 2版 05).
enum LuggageConsent: String {
    case unasked, allowed, declined

    static let key = "luggageCheckConsent"

    static var current: LuggageConsent {
        UserDefaults.standard.string(forKey: key).flatMap(LuggageConsent.init) ?? .unasked
    }
}

extension LuggageFacts {
    /// Checks kept on the trip's stays, asked through the relay when the person allowed it.
    @MainActor static func live(trip: Trip, relay: FactRelay = .shared) -> LuggageFacts {
        LuggageFacts(
            stored: { id in trip.items.first { $0.id == id }?.luggageFact },
            check: { stay in await relay.luggage(title: stay.title, placeID: stay.placeID, area: stay.area) },
            save: { id, fact in
                guard let item = trip.items.first(where: { $0.id == id }) else { return }
                item.luggageFact = fact
                try? item.modelContext?.save()
            },
            allowed: { LuggageConsent.current == .allowed }
        )
    }
}

extension LuggagePrefetch {
    /// Checks the stays of the next two days when Romy comes to the front (Notion 02 §6-4「いつ調べるか」),
    /// one after another, only when the person allowed it.
    @MainActor static func run(trips: [Trip], relay: FactRelay = .shared, now: Date = .now) async {
        guard LuggageConsent.current == .allowed else { return }
        let text = DateText(calendar: .current, holidays: .bundled)
        var items: [UUID: ItineraryItem] = [:]
        var stays: [Stay] = []
        for trip in trips {
            let days = ItineraryDays(dates: trip.dates, text: text)
            for item in trip.items where item.kind == .stay {
                items[item.id] = item
                stays.append(Stay(
                    id: item.id, title: item.title, placeID: item.placeID, area: item.area, latitude: item.latitude,
                    checkInDate: days.date(of: item.day), stayKind: item.stayKind, fact: item.luggageFact
                ))
            }
        }
        for stay in due(stays, now: now, calendar: text.calendar) {
            guard let fact = await relay.luggage(title: stay.title, placeID: stay.placeID, area: stay.area),
                  let item = items[stay.id], !item.isDeleted else { continue }
            item.luggageFact = fact
            try? item.modelContext?.save()
        }
    }
}
