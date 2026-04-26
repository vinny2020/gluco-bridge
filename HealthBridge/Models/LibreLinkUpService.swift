// Models/LibreLinkUpService.swift

import Foundation

// MARK: - URLSession protocol for testability

protocol URLSessionProtocol: Sendable {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

extension URLSession: URLSessionProtocol {}

// MARK: - LibreLinkUp API actor

actor LibreLinkUpService {
    private let session: URLSessionProtocol
    private let baseURL = URL(string: "https://api.libreview.io")!

    init(session: URLSessionProtocol = URLSession.shared) {
        self.session = session
    }

    // MARK: - Login

    func login(email: String, password: String) async throws -> LLUAuthTicket {
        let bodyData = try JSONEncoder().encode(LLULoginRequest(email: email, password: password))
        var loginURL = baseURL.appendingPathComponent("llu/auth/login")

        // Follow at most one regional redirect
        for attempt in 0...1 {
            var request = URLRequest(url: loginURL)
            request.httpMethod = "POST"
            applyHeaders(&request, token: nil)
            request.httpBody = bodyData

            let (data, response) = try await performRequest(request)
            try validate(response: response)

            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw LLUError.decodingError(NSError(domain: "HealthBridge", code: 0,
                    userInfo: [NSLocalizedDescriptionKey: "Non-JSON response from LibreLinkUp"]))
            }

            let dataDict = json["data"] as? [String: Any]

            // Regional redirect: {"status":0,"data":{"redirect":true,"region":"us"}}
            if let redirect = dataDict?["redirect"] as? Bool, redirect,
               let region = dataDict?["region"] as? String,
               attempt == 0 {
                let regionalBase = "https://api-\(region).libreview.io"
                if let url = URL(string: regionalBase)?.appendingPathComponent("llu/auth/login") {
                    loginURL = url
                }
                continue
            }

            guard let ticketDict = dataDict?["authTicket"] as? [String: Any],
                  let token = ticketDict["token"] as? String,
                  let expires = ticketDict["expires"] as? Int else {
                throw LLUError.unauthorized
            }

            return LLUAuthTicket(token: token, expires: expires)
        }

        throw LLUError.unauthorized
    }

    // MARK: - Connections

    func fetchConnections(token: String) async throws -> [LLUPatient] {
        let url = baseURL.appendingPathComponent("llu/connections")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        applyHeaders(&request, token: token)

        let (data, response) = try await performRequest(request)
        try validate(response: response)

        do {
            let decoded = try JSONDecoder().decode(LLUConnectionsResponse.self, from: data)
            return decoded.data ?? []
        } catch let error as LLUError {
            throw error
        } catch {
            throw LLUError.decodingError(error)
        }
    }

    // MARK: - Glucose graph

    func fetchGlucoseGraph(token: String, patientId: String) async throws -> [LLUGlucoseMeasurement] {
        let url = baseURL.appendingPathComponent("llu/connections/\(patientId)/graph")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        applyHeaders(&request, token: token)

        let (data, response) = try await performRequest(request)
        try validate(response: response)

        do {
            let decoded = try JSONDecoder().decode(LLUGraphResponse.self, from: data)
            guard let graphData = decoded.data else { throw LLUError.noData }

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
        } catch {
            throw LLUError.decodingError(error)
        }
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

    private func applyHeaders(_ request: inout URLRequest, token: String?) {
        request.setValue("application/json",  forHTTPHeaderField: "Content-Type")
        request.setValue("llu.ios",           forHTTPHeaderField: "product")
        request.setValue("4.7.0",             forHTTPHeaderField: "version")
        request.setValue("Mozilla/5.0",       forHTTPHeaderField: "User-Agent")
        request.setValue("no-cache",          forHTTPHeaderField: "Cache-Control")
        request.setValue("no-cache",          forHTTPHeaderField: "Pragma")
        request.setValue("gzip, deflate, br", forHTTPHeaderField: "Accept-Encoding")
        request.setValue("keep-alive",        forHTTPHeaderField: "Connection")
        if let token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
    }
}
