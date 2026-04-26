// Models/LibreLinkUpModels.swift

import Foundation

// MARK: - Login

struct LLULoginRequest: Encodable {
    let email: String
    let password: String
}

struct LLULoginResponse: Decodable {
    let data: LLULoginData?
    let status: Int?
}

struct LLULoginData: Decodable {
    let authTicket: LLUAuthTicket?
    let user: LLUUser?
}

struct LLUAuthTicket: Decodable {
    let token: String
    let expires: Int
}

struct LLUUser: Decodable {
    let firstName: String?
    let lastName: String?
}

// MARK: - Connections

struct LLUConnectionsResponse: Decodable {
    let data: [LLUPatient]?
    let status: Int?
}

struct LLUPatient: Decodable {
    let patientId: String
    let firstName: String
    let lastName: String

    var displayName: String {
        let full = "\(firstName) \(lastName)".trimmingCharacters(in: .whitespacesAndNewlines)
        return full.isEmpty ? patientId : full
    }
}

// MARK: - Glucose Graph

struct LLUGraphResponse: Decodable {
    let data: LLUGraphData?
    let status: Int?
}

struct LLUGraphData: Decodable {
    let connection: LLUConnection?
    let graphData: [LLUGlucoseMeasurement]?
}

struct LLUConnection: Decodable {
    let glucoseMeasurement: LLUGlucoseMeasurement?
    let patientId: String?
}

struct LLUGlucoseMeasurement: Decodable {
    let FactoryTimestamp: String?
    let Timestamp: String
    let Value: Int
    let TrendArrow: Int?

    var date: Date {
        LibreLinkUpDateParser.parseDate(
            factoryTimestamp: FactoryTimestamp,
            timestamp: Timestamp
        ) ?? Date()
    }

    var mgdl: Double { Double(Value) }
}

// MARK: - Date parsing

enum LibreLinkUpDateParser {
    static func parseDate(factoryTimestamp: String?, timestamp: String) -> Date? {
        if let factoryTimestamp, !factoryTimestamp.isEmpty,
           let date = utcFormatter.date(from: factoryTimestamp) {
            return date
        }

        if timestamp.contains("T") {
            if let date = iso8601WithFractional.date(from: timestamp) { return date }
            if let date = iso8601.date(from: timestamp) { return date }
        }

        return localFormatter.date(from: timestamp)
    }

    private static let utcFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "M/d/yyyy h:mm:ss a"
        f.timeZone = TimeZone(secondsFromGMT: 0)
        return f
    }()

    private static let localFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "M/d/yyyy h:mm:ss a"
        f.timeZone = TimeZone.current
        return f
    }()

    private nonisolated(unsafe) static let iso8601WithFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private nonisolated(unsafe) static let iso8601: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()
}

// MARK: - Errors

enum LLUError: Error, LocalizedError, Equatable {
    case unauthorized
    case networkError(Error)
    case noData
    case decodingError(Error)
    case redirectRequired(String)

    static func == (lhs: LLUError, rhs: LLUError) -> Bool {
        switch (lhs, rhs) {
        case (.unauthorized, .unauthorized):             return true
        case (.noData, .noData):                         return true
        case (.networkError, .networkError):             return true
        case (.decodingError, .decodingError):           return true
        case (.redirectRequired(let a), .redirectRequired(let b)): return a == b
        default:                                         return false
        }
    }

    var errorDescription: String? {
        switch self {
        case .unauthorized:            return "LibreLinkUp authorization failed. Check your credentials."
        case .networkError(let e):     return "Network error: \(e.localizedDescription)"
        case .noData:                  return "No glucose data returned."
        case .decodingError(let e):    return "Decoding error: \(e.localizedDescription)"
        case .redirectRequired(let r): return "Region redirect required: \(r)"
        }
    }
}
