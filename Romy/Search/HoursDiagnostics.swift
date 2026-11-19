import Foundation
import OSLog

/// Developer diagnostics only. Never record a place, date, URL, token, session or response body.
nonisolated enum HoursDiagnostics {
    enum Code: String {
        case confirmed, conflicting, unknown
        case apiUnconfigured = "api_unconfigured"
        case nameMismatch = "name_mismatch"
        case addressMismatch = "address_mismatch"
        case dateMismatch = "date_mismatch"
        case noOfficialSource = "no_official_source"
        case invalidHours = "invalid_hours"
        case noHours = "no_hours"
        case deviceLimit = "device_limit"
        case budgetLimit = "budget_limit"
        case sessionLimit = "session_limit"
        case searchEmpty = "search_empty"
        case placeNotMatched = "place_not_matched"
        case readerEmpty = "reader_empty"
        case readerInvalidJSON = "reader_invalid_json"
        case searchFailed = "search_failed"
        case readerFailed = "reader_failed"
        case internalError = "internal_error"
        case cachedUnknown = "cached_unknown"
        case missingAddress = "missing_address"
        case missingConfig = "missing_config"
        case clientSessionLimit = "client_session_limit"
        case transportFailed = "transport_failed"
        case httpRejected = "http_rejected"
        case responseInvalid = "response_invalid"
    }

    private static let logger = Logger(subsystem: "com.KitadeR.Romy", category: "Hours")

    static func record(_ code: Code, httpStatus: Int = 0) {
        logger.debug("hours_result code=\(code.rawValue, privacy: .public) http_status=\(httpStatus)")
    }
}
