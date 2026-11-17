import Foundation

/// 中継へ送る文と店舗情報を入口で分ける。位置情報や旅程全体は送信しない。
struct SceneAI {
    var interpret: (String, UUID) async -> ScenePreferences?
    var hours: (ProposalPlace, Date, UUID) async -> SceneHours?
    static let live = SceneAI(
        interpret: { text, session in
            await FactRelay.shared.scene(["operation": "interpret", "text": text], session: session)?.preferences
        },
        hours: { place, date, session in
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "yyyy-MM-dd"
            guard let address = place.address, !address.isEmpty else { return nil }
            return await FactRelay.shared.scene([
                "operation": "hours", "name": place.name, "address": address,
                "date": formatter.string(from: date), "timeZone": TimeZone.current.identifier
            ], session: session)?.hours
        }
    )
}

struct SceneAIReply: Decodable {
    let preferences: ScenePreferences?
    let hours: SceneHours?
    let reason: String?
}

extension FactRelay {
    func scene(_ fields: [String: String], session sceneID: UUID) async -> SceneAIReply? {
        guard let baseURL else { return nil }
        var body = fields
        body["session"] = sceneID.uuidString
        var request = URLRequest(url: baseURL.appending(path: "v1/scene"))
        request.httpMethod = "POST"
        request.timeoutInterval = 70
        request.httpBody = try? JSONEncoder().encode(body)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(Self.deviceID, forHTTPHeaderField: "X-Romy-Device")
        if let token { request.setValue(token, forHTTPHeaderField: "X-Romy-Token") }
        guard let (data, response) = try? await session.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return try? JSONDecoder().decode(SceneAIReply.self, from: data)
    }
}
