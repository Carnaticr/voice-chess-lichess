import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct LichessError: LocalizedError, Sendable {
    public let message: String
    public let status: Int?
    public var errorDescription: String? { message }
}

/// Lichess Board API client. https://lichess.org/api#tag/Board
public struct LichessClient: Sendable {
    static let baseString = "https://lichess.org"

    /// Page where the player creates a personal token with the scopes this app needs.
    public static let tokenPage = URL(string: baseString + "/account/oauth/token/create?scopes%5B%5D=board:play&scopes%5B%5D=challenge:write&description=Voice+Chess")

    public static func gameURL(_ gameId: String) -> URL? { URL(string: "\(baseString)/\(gameId)") }

    private let token: String
    private let session: URLSession

    public init(token: String, session: URLSession = .shared) {
        self.token = token
        self.session = session
    }

    private func request(_ path: String, method: String = "GET", form: [String: String]? = nil, accept: String? = nil) -> URLRequest {
        // Paths are built from Lichess ids (alphanumeric), so plain concatenation is safe.
        var req = URLRequest(url: URL(string: Self.baseString + path) ?? URL(filePath: "/"))
        req.httpMethod = method
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let accept { req.setValue(accept, forHTTPHeaderField: "Accept") }
        if let form {
            req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            req.httpBody = Self.formBody(form).data(using: .utf8)
        }
        return req
    }

    static func formBody(_ form: [String: String]) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return form.sorted { $0.key < $1.key }
            .map { "\($0.key.addingPercentEncoding(withAllowedCharacters: allowed) ?? $0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: allowed) ?? $0.value)" }
            .joined(separator: "&")
    }

    private func send<T: Decodable>(_ req: URLRequest, as type: T.Type) async throws -> T {
        let (data, response) = try await session.data(for: req)
        try Self.check(response, data: data)
        return try JSONDecoder().decode(T.self, from: data)
    }

    private func sendIgnoringBody(_ req: URLRequest) async throws {
        let (data, response) = try await session.data(for: req)
        try Self.check(response, data: data)
    }

    static func check(_ response: URLResponse, data: Data?) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard (200..<300).contains(http.statusCode) else {
            var message = "HTTP \(http.statusCode)"
            if let data, let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                if let e = obj["error"] as? String { message = e }
                else if let e = obj["error"], let d = try? JSONSerialization.data(withJSONObject: e),
                        let s = String(data: d, encoding: .utf8) { message = s }
            }
            throw LichessError(message: message, status: http.statusCode)
        }
    }

    // MARK: Calls

    public func account() async throws -> Account {
        try await send(request("/api/account"), as: Account.self)
    }

    /// Scopes granted to this token, or nil if Lichess doesn't know it.
    public func scopes() async throws -> [String]? {
        var req = URLRequest(url: URL(string: Self.baseString + "/api/token/test") ?? URL(filePath: "/"))
        req.httpMethod = "POST"
        req.httpBody = token.data(using: .utf8)
        let (data, _) = try await session.data(for: req)
        let result = try JSONDecoder().decode([String: TokenTestResult?].self, from: data)
        guard let entry = result[token] ?? nil else { return nil }
        return entry.scopes?.split(separator: ",").map(String.init) ?? []
    }

    public func move(gameId: String, uci: String) async throws {
        try await sendIgnoringBody(request("/api/board/game/\(gameId)/move/\(uci)", method: "POST"))
    }

    public func resign(gameId: String) async throws {
        try await sendIgnoringBody(request("/api/board/game/\(gameId)/resign", method: "POST"))
    }

    public func abort(gameId: String) async throws {
        try await sendIgnoringBody(request("/api/board/game/\(gameId)/abort", method: "POST"))
    }

    public func draw(gameId: String, accept: Bool) async throws {
        try await sendIgnoringBody(request("/api/board/game/\(gameId)/draw/\(accept ? "yes" : "no")", method: "POST"))
    }

    /// Starts a game against Stockfish; returns the game id.
    public func challengeAI(level: Int, limitSeconds: Int, increment: Int, color: String) async throws -> String {
        struct Created: Decodable { let id: String }
        let req = request("/api/challenge/ai", method: "POST", form: [
            "level": String(level), "clock.limit": String(limitSeconds), "clock.increment": String(increment), "color": color,
        ])
        return try await send(req, as: Created.self).id
    }

    public func export(gameId: String) async throws -> GameExport {
        try await send(request("/game/export/\(gameId)?evals=true&accuracy=true&opening=true&clocks=false", accept: "application/json"),
                       as: GameExport.self)
    }

    // MARK: Streams

    /// The account's event stream (game starts/finishes, challenges).
    public func accountEvents() -> AsyncThrowingStream<AccountEvent, Error> {
        ndjson(request("/api/stream/event"))
    }

    /// Board state stream for one game; finishes when the game ends.
    public func gameEvents(gameId: String) -> AsyncThrowingStream<GameStreamEvent, Error> {
        ndjson(request("/api/board/game/stream/\(gameId)"))
    }

    /// Real-time seek. The request stays open until a game starts (cancel the task to cancel the seek).
    public func seek(minutes: Int, increment: Int, rated: Bool) async throws {
        let req = request("/api/board/seek", method: "POST", form: [
            "time": String(minutes), "increment": String(increment), "rated": String(rated), "color": "random", "variant": "standard",
        ])
        let (bytes, response) = try await session.bytes(for: req)
        try Self.check(response, data: nil)
        for try await _ in bytes.lines {}
    }

    private func ndjson<T: Decodable & Sendable>(_ req: URLRequest) -> AsyncThrowingStream<T, Error> {
        let session = session
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let (bytes, response) = try await session.bytes(for: req)
                    try Self.check(response, data: nil)
                    let decoder = JSONDecoder()
                    for try await line in bytes.lines {
                        guard !line.isEmpty, let data = line.data(using: .utf8) else { continue } // keep-alive
                        if let value = try? decoder.decode(T.self, from: data) { continuation.yield(value) }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
