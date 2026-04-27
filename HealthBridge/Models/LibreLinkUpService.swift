// Models/LibreLinkUpService.swift

import Foundation
import OSLog
import CryptoKit

// MARK: - URLSession protocol for testability

protocol URLSessionProtocol: Sendable {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

extension URLSession: URLSessionProtocol {}

// MARK: - LibreLinkUp API actor

actor LibreLinkUpService {
    private static let log = Logger(subsystem: "com.xaymaca.healthbridge", category: "LLU")
    private let session: URLSessionProtocol
    private var resolvedBaseURL: URL
    private(set) var currentRegion: String?
    /// SHA256 of the LLU user id, hex-encoded — sent as the `account-id` header
    /// on authenticated requests. LibreView started enforcing this around the 4.16.x
    /// client release; without it `/llu/connections` returns HTTP 400 RequiredHeaderMissing.
    private(set) var currentAccountId: String?

    init(session: URLSessionProtocol = URLSession.shared,
         region: String? = nil,
         accountId: String? = nil) {
        self.session = session
        if let region, !region.isEmpty {
            self.resolvedBaseURL = URL(string: "https://api-\(region).libreview.io")!
            self.currentRegion = region
        } else {
            self.resolvedBaseURL = URL(string: "https://api.libreview.io")!
            self.currentRegion = nil
        }
        self.currentAccountId = (accountId?.isEmpty == false) ? accountId : nil
    }

    /// Computes the LLU `account-id` header value: SHA256 of the user id, lowercase hex.
    static func hashedAccountId(forUserId userId: String) -> String {
        let digest = SHA256.hash(data: Data(userId.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// Detects the LLU regional-redirect response shape and updates state.
    /// Response shape: `{"status":0,"data":{"redirect":true,"region":"us"}}`.
    /// Returns true if a redirect was handled — callers should retry the request.
    private func handleRegionalRedirect(_ data: Data) -> Bool {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let dataDict = json["data"] as? [String: Any],
              let redirect = dataDict["redirect"] as? Bool, redirect,
              let region = dataDict["region"] as? String,
              let url = URL(string: "https://api-\(region).libreview.io") else {
            return false
        }
        resolvedBaseURL = url
        currentRegion = region
        return true
    }

    /// Detects the LLU "client too old" response and throws a clear error.
    /// Response shape: `{"status": 920, "data": {"minimumVersion": "X.Y.Z"}}`.
    /// LibreView increments the required client version periodically; surfacing
    /// it explicitly avoids the otherwise opaque "type mismatch at data" decode error.
    private func checkMinimumVersionResponse(_ data: Data) throws {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let status = json["status"] as? Int, status == 920,
              let dataDict = json["data"] as? [String: Any],
              let minVersion = dataDict["minimumVersion"] as? String else {
            return
        }
        let detail = "LibreLinkUp requires client version \(minVersion) or newer; we send \(Self.clientVersion). Bump LibreLinkUpService.clientVersion."
        throw LLUError.decodingError(NSError(domain: "HealthBridge.LibreLinkUp", code: 920,
                                             userInfo: [NSLocalizedDescriptionKey: detail]))
    }

    // MARK: - Login

    func login(email: String, password: String) async throws -> LLUAuthTicket {
        let bodyData = try JSONEncoder().encode(LLULoginRequest(email: email, password: password))

        // Follow at most one regional redirect
        for attempt in 0...1 {
            let loginURL = resolvedBaseURL.appendingPathComponent("llu/auth/login")
            var request = URLRequest(url: loginURL)
            request.httpMethod = "POST"
            applyHeaders(&request, token: nil)
            request.httpBody = bodyData

            let (data, response) = try await performRequest(request)
            try validate(response: response)

            // Regional redirect: {"status":0,"data":{"redirect":true,"region":"us"}}
            // Updates resolvedBaseURL + currentRegion so subsequent calls hit the same region.
            if attempt == 0, handleRegionalRedirect(data) {
                continue
            }

            try checkMinimumVersionResponse(data)

            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw LLUError.decodingError(NSError(domain: "HealthBridge", code: 0,
                    userInfo: [NSLocalizedDescriptionKey: "Non-JSON response from LibreLinkUp"]))
            }

            let dataDict = json["data"] as? [String: Any]

            guard let ticketDict = dataDict?["authTicket"] as? [String: Any],
                  let token = ticketDict["token"] as? String,
                  let expires = ticketDict["expires"] as? Int else {
                throw LLUError.unauthorized
            }

            // LLU 4.16+ requires `account-id` (SHA256 of user.id) on authenticated calls.
            // Extract and stash it now so fetchConnections / fetchGlucoseGraph can send it.
            if let userDict = dataDict?["user"] as? [String: Any],
               let userId = userDict["id"] as? String, !userId.isEmpty {
                currentAccountId = Self.hashedAccountId(forUserId: userId)
            }

            return LLUAuthTicket(token: token, expires: expires)
        }

        throw LLUError.unauthorized
    }

    // MARK: - Connections

    func fetchConnections(token: String) async throws -> [LLUPatient] {
        for attempt in 0...1 {
            let url = resolvedBaseURL.appendingPathComponent("llu/connections")
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            applyHeaders(&request, token: token)

            let (data, response) = try await performRequest(request)
            try validate(response: response)

            if attempt == 0, handleRegionalRedirect(data) {
                continue
            }

            do {
                try checkMinimumVersionResponse(data)
                let decoded = try JSONDecoder().decode(LLUConnectionsResponse.self, from: data)
                return decoded.data ?? []
            } catch let error as LLUError {
                throw error
            } catch let error as DecodingError {
                throw LLUError.decodingError(Self.describeDecodingError(error, endpoint: "fetchConnections"))
            } catch {
                throw LLUError.decodingError(error)
            }
        }
        throw LLUError.noData
    }

    // MARK: - Glucose graph

    func fetchGlucoseGraph(token: String, patientId: String) async throws -> [LLUGlucoseMeasurement] {
        for attempt in 0...1 {
            let url = resolvedBaseURL.appendingPathComponent("llu/connections/\(patientId)/graph")
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            applyHeaders(&request, token: token)

            let (data, response) = try await performRequest(request)
            try validate(response: response)

            if attempt == 0, handleRegionalRedirect(data) {
                continue
            }

            do {
                try checkMinimumVersionResponse(data)
                let decoded = try JSONDecoder().decode(LLUGraphResponse.self, from: data)
                guard let graphData = decoded.data else {
                    let snippet = String(data: data, encoding: .utf8)?.prefix(400).description ?? "<binary>"
                    Self.log.error("graph: data==nil, status=\(decoded.status ?? -1, privacy: .public), body=\(snippet, privacy: .public)")
                    throw LLUError.apiError(status: decoded.status, snippet: snippet)
                }
                Self.log.info("graph: ok, history=\(graphData.graphData?.count ?? 0, privacy: .public), current=\(graphData.connection?.glucoseMeasurement != nil ? 1 : 0, privacy: .public)")

                var readings: [LLUGlucoseMeasurement] = []
                if let current = graphData.connection?.glucoseMeasurement {
                    readings.append(current)
                }
                if let history = graphData.graphData {
                    readings.append(contentsOf: history)
                }
                return readings
            } catch let error as LLUError {
                throw error
            } catch let error as DecodingError {
                throw LLUError.decodingError(Self.describeDecodingError(error, endpoint: "fetchGlucoseGraph"))
            } catch {
                throw LLUError.decodingError(error)
            }
        }
        throw LLUError.noData
    }

    // MARK: - Helpers

    private func performRequest(_ request: URLRequest) async throws -> (Data, URLResponse) {
        do {
            return try await session.data(for: request)
        } catch {
            throw LLUError.networkError(error)
        }
    }

    private func validate(response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { return }
        if http.statusCode == 401 { throw LLUError.unauthorized }
    }

    /// LLU client version sent in the `version` header. Bump this when the API
    /// responds with `{"status": 920, "data": {"minimumVersion": "X.Y.Z"}}`,
    /// which means our value is too old. Last bumped 2026-04-26.
    private static let clientVersion = "4.16.0"

    private func applyHeaders(_ request: inout URLRequest, token: String?) {
        request.setValue("application/json",  forHTTPHeaderField: "Content-Type")
        request.setValue("llu.ios",           forHTTPHeaderField: "product")
        request.setValue(Self.clientVersion,  forHTTPHeaderField: "version")
        request.setValue("Mozilla/5.0",       forHTTPHeaderField: "User-Agent")
        request.setValue("no-cache",          forHTTPHeaderField: "Cache-Control")
        request.setValue("no-cache",          forHTTPHeaderField: "Pragma")
        request.setValue("gzip, deflate, br", forHTTPHeaderField: "Accept-Encoding")
        request.setValue("keep-alive",        forHTTPHeaderField: "Connection")
        if let accountId = currentAccountId {
            request.setValue(accountId,       forHTTPHeaderField: "account-id")
        }
        if let token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
    }

    /// Build a detailed NSError describing a Swift `DecodingError`, including
    /// the failing endpoint and coding path. Does NOT include payload values,
    /// so it stays compliant with the no-glucose-logging privacy rule.
    private static func describeDecodingError(_ error: DecodingError, endpoint: String) -> NSError {
        let pathString: (DecodingError.Context) -> String = { ctx in
            ctx.codingPath.map { $0.stringValue }.joined(separator: ".")
        }
        let detail: String
        switch error {
        case .keyNotFound(let key, let ctx):
            let p = pathString(ctx)
            detail = "\(endpoint): missing key '\(key.stringValue)'\(p.isEmpty ? "" : " at \(p)")"
        case .typeMismatch(let type, let ctx):
            let p = pathString(ctx)
            detail = "\(endpoint): type mismatch (expected \(type))\(p.isEmpty ? "" : " at \(p)")"
        case .valueNotFound(let type, let ctx):
            let p = pathString(ctx)
            detail = "\(endpoint): null where \(type) expected\(p.isEmpty ? "" : " at \(p)")"
        case .dataCorrupted(let ctx):
            let p = pathString(ctx)
            detail = "\(endpoint): data corrupted\(p.isEmpty ? "" : " at \(p)") — \(ctx.debugDescription)"
        @unknown default:
            detail = "\(endpoint): \(error.localizedDescription)"
        }
        return NSError(domain: "HealthBridge.LibreLinkUp", code: 1001,
                       userInfo: [NSLocalizedDescriptionKey: detail])
    }
}
