import Foundation

/// 一言の解釈と営業時間の確認を入口で分ける。位置情報や旅程全体は送信しない。
struct SceneAI {
    var interpret: (String, UUID) async -> ScenePreferences?
    var hours: (ProposalPlace, Date, UUID) async -> SceneHours?
    static let live = SceneAI(
        interpret: { text, _ in
            // 一言は端末内のApple Intelligenceだけで解釈し、端末の外へ送らない。
            // 非対応端末では一言の入力欄を出さないため、ここでは中継を使わない。
            await OnDeviceIntake.interpret(text)
        },
        hours: { place, date, session in
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "yyyy-MM-dd"
            guard let address = place.address, !address.isEmpty else {
                HoursDiagnostics.record(.missingAddress)
                return nil
            }
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
    let diagnostic: Diagnostic?

    struct Diagnostic: Decodable {
        let code: String
    }
}

extension FactRelay {
    func scene(_ fields: [String: String], session sceneID: UUID) async -> SceneAIReply? {
        let checkingHours = fields["operation"] == "hours"
        guard let baseURL else {
            if checkingHours { HoursDiagnostics.record(.missingConfig) }
            return nil
        }
        var body = fields
        body["session"] = sceneID.uuidString
        var request = URLRequest(url: baseURL.appending(path: "v1/scene"))
        request.httpMethod = "POST"
        request.timeoutInterval = 70
        request.httpBody = try? JSONEncoder().encode(body)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(Self.deviceID, forHTTPHeaderField: "X-Romy-Device")
        if let token { request.setValue(token, forHTTPHeaderField: "X-Romy-Token") }
        do {
            let (data, response) = try await session.data(for: request)
            guard let response = response as? HTTPURLResponse, response.statusCode == 200 else {
                if checkingHours { HoursDiagnostics.record(.httpRejected, httpStatus: (response as? HTTPURLResponse)?.statusCode ?? 0) }
                return nil
            }
            guard let reply = try? JSONDecoder().decode(SceneAIReply.self, from: data) else {
                if checkingHours { HoursDiagnostics.record(.responseInvalid) }
                return nil
            }
            if checkingHours {
                HoursDiagnostics.record(reply.diagnostic.flatMap { HoursDiagnostics.Code(rawValue: $0.code) } ?? .unknown)
            }
            return reply
        } catch {
            if checkingHours, !Task.isCancelled { HoursDiagnostics.record(.transportFailed) }
            return nil
        }
    }
}
