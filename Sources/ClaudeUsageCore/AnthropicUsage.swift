import Foundation

/// One usage window from Anthropic's `/api/oauth/usage` response. Mirrors the shape Claude
/// Code's daemon uses internally — `utilization` is a 0-100 percentage, `resetsAt` is an
/// ISO 8601 timestamp with fractional seconds and a timezone offset.
public struct AnthropicUsageWindow: Codable, Equatable, Sendable {
    public let utilization: Double
    public let resetsAt: Date?

    public init(utilization: Double, resetsAt: Date?) {
        self.utilization = utilization
        self.resetsAt = resetsAt
    }

    enum CodingKeys: String, CodingKey {
        case utilization
        case resetsAt = "resets_at"
    }

    /// Convenience for the only `resetsAt` consumer in the app: time until reset.
    public func remaining(from now: Date = Date()) -> TimeInterval? {
        guard let resetsAt else { return nil }
        return max(0, resetsAt.timeIntervalSince(now))
    }
}

/// Decoded body of `GET /api/oauth/usage`. Only the fields we actually use are surfaced.
public struct AnthropicUsage: Codable, Equatable, Sendable {
    public let fiveHour: AnthropicUsageWindow
    public let sevenDay: AnthropicUsageWindow?
    public let sevenDayOpus: AnthropicUsageWindow?
    public let sevenDaySonnet: AnthropicUsageWindow?
    /// Wall-clock time the response was received. Set by the client, not the server.
    public var fetchedAt: Date

    public init(
        fiveHour: AnthropicUsageWindow,
        sevenDay: AnthropicUsageWindow? = nil,
        sevenDayOpus: AnthropicUsageWindow? = nil,
        sevenDaySonnet: AnthropicUsageWindow? = nil,
        fetchedAt: Date = Date()
    ) {
        self.fiveHour = fiveHour
        self.sevenDay = sevenDay
        self.sevenDayOpus = sevenDayOpus
        self.sevenDaySonnet = sevenDaySonnet
        self.fetchedAt = fetchedAt
    }

    enum CodingKeys: String, CodingKey {
        case fiveHour = "five_hour"
        case sevenDay = "seven_day"
        case sevenDayOpus = "seven_day_opus"
        case sevenDaySonnet = "seven_day_sonnet"
        // `fetchedAt` is stamped on by the client after decode; the server never sends it.
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.fiveHour = try c.decode(AnthropicUsageWindow.self, forKey: .fiveHour)
        self.sevenDay = try c.decodeIfPresent(AnthropicUsageWindow.self, forKey: .sevenDay)
        self.sevenDayOpus = try c.decodeIfPresent(AnthropicUsageWindow.self, forKey: .sevenDayOpus)
        self.sevenDaySonnet = try c.decodeIfPresent(AnthropicUsageWindow.self, forKey: .sevenDaySonnet)
        self.fetchedAt = Date()
    }

    /// Decodes the server response. Server payloads do not contain `fetchedAt`; the client
    /// stamps it on after a successful fetch.
    public static func decode(_ data: Data, fetchedAt: Date = Date()) throws -> AnthropicUsage {
        let decoder = JSONDecoder()
        // ISO8601DateFormatter isn't Sendable, so it can't live in a file-private `let`
        // under Swift 6 strict concurrency. Constructing per-call is cheap enough and
        // keeps the formatter local to this closure.
        decoder.dateDecodingStrategy = .custom { dec in
            let container = try dec.singleValueContainer()
            let raw = try container.decode(String.self)
            let fractional = ISO8601DateFormatter()
            fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let d = fractional.date(from: raw) { return d }
            let plain = ISO8601DateFormatter()
            plain.formatOptions = [.withInternetDateTime]
            if let d = plain.date(from: raw) { return d }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unrecognized date: \(raw)"
            )
        }
        var usage = try decoder.decode(AnthropicUsage.self, from: data)
        usage.fetchedAt = fetchedAt
        return usage
    }
}

public enum AnthropicUsageError: Error, Equatable, Sendable {
    /// Keychain blob missing or malformed — Claude Code probably isn't logged in.
    case tokenUnavailable
    /// 401 from the server. Caller should not retry until the user re-authenticates Claude Code.
    case authenticationFailed
    /// 429. `retryAfter` is parsed from the `Retry-After` header when present.
    case rateLimited(retryAfter: TimeInterval?)
    case server(Int)
    case invalidResponse
    case decoding(String)
    case network(String)
}

/// Fetches usage from Anthropic's private `/api/oauth/usage` endpoint using the OAuth
/// access token that Claude Code stores in the macOS Keychain.
///
/// This endpoint is not part of Anthropic's public API surface. It can change or disappear
/// without notice. Failures fall back to local JSONL estimation in the caller.
public actor AnthropicUsageClient {
    public static let endpointString = "https://api.anthropic.com/api/oauth/usage"
    /// Anthropic-version header value Claude Code sends. Required by the endpoint.
    public static let anthropicVersion = "2023-06-01"

    private let session: URLSession
    private let credentialsProvider: @Sendable () throws -> KeychainCredentials

    /// Cached credentials so we don't re-enter the keychain (and trigger an ACL dialog)
    /// on every 90s fetch. We invalidate it five minutes before the stored expiry.
    private var cached: KeychainCredentials?
    private static let expirySafetyMargin: TimeInterval = 300

    public init(
        session: URLSession = .shared,
        credentialsProvider: @escaping @Sendable () throws -> KeychainCredentials = { try KeychainTokenReader.readClaudeCredentials() }
    ) {
        self.session = session
        self.credentialsProvider = credentialsProvider
    }

    /// Manually flush the cached token. Use this when authentication fails so the next
    /// fetch re-reads the keychain (Claude Code's daemon may have rotated the token).
    public func invalidateTokenCache() {
        cached = nil
    }

    private func currentToken() throws -> String {
        if let cached, cached.expiresAt.map({ $0.timeIntervalSinceNow > Self.expirySafetyMargin }) ?? false {
            return cached.accessToken
        }
        let creds = try credentialsProvider()
        cached = creds
        return creds.accessToken
    }

    /// Fetch usage. Pass `usingToken` to skip the keychain read — useful when the caller
    /// already obtained a token via `KeychainTokenReader` and wants to avoid triggering
    /// the keychain ACL dialog a second time (which can hang on background threads).
    public func fetch(usingToken explicit: String? = nil) async throws -> AnthropicUsage {
        let token: String
        if let explicit, !explicit.isEmpty {
            token = explicit
            // The explicit token came straight from the keychain — refresh our cache so
            // the next no-arg fetch reuses it instead of prompting again.
            cached = KeychainCredentials(accessToken: explicit, expiresAt: cached?.expiresAt)
        } else {
            do {
                token = try currentToken()
            } catch KeychainTokenReader.Failure.notFound {
                throw AnthropicUsageError.tokenUnavailable
            } catch {
                throw AnthropicUsageError.tokenUnavailable
            }
        }

        guard let url = URL(string: Self.endpointString) else {
            throw AnthropicUsageError.invalidResponse
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(Self.anthropicVersion, forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 10

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw AnthropicUsageError.network(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw AnthropicUsageError.invalidResponse
        }
        switch http.statusCode {
        case 200:
            do {
                return try AnthropicUsage.decode(data)
            } catch {
                throw AnthropicUsageError.decoding(String(describing: error))
            }
        case 401, 403:
            // Cached token may be stale (Claude Code rotated it). Drop the cache so the
            // next attempt re-reads the keychain.
            cached = nil
            throw AnthropicUsageError.authenticationFailed
        case 429:
            let retry = (http.value(forHTTPHeaderField: "Retry-After")).flatMap(Double.init)
            throw AnthropicUsageError.rateLimited(retryAfter: retry)
        default:
            throw AnthropicUsageError.server(http.statusCode)
        }
    }
}
