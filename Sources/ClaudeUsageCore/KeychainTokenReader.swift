import Foundation
import Security

/// Reads the OAuth credential blob Claude Code stores in the macOS Keychain
/// (`Claude Code-credentials`). The blob is JSON with the credential dict nested
/// under `claudeAiOauth`:
///
///   { "claudeAiOauth": { "accessToken": "...", "refreshToken": "...", ... } }
///
/// Some older Claude Code builds stored the inner blob as a JSON-encoded string
/// instead of an object — we handle both shapes.
///
/// We only need the `accessToken` — Claude Code's daemon refreshes it
/// proactively, so re-reading on each request gives a fresh token.
public struct KeychainCredentials: Equatable, Sendable {
    public let accessToken: String
    /// Parsed from the blob's `expiresAt` field when present. Claude Code stores it
    /// as a Unix epoch in milliseconds; older builds may use seconds. Both handled.
    public let expiresAt: Date?

    public init(accessToken: String, expiresAt: Date?) {
        self.accessToken = accessToken
        self.expiresAt = expiresAt
    }
}

public enum KeychainTokenReader {
    public static let service = "Claude Code-credentials"

    public enum Failure: Swift.Error, Equatable {
        case notFound
        case unexpectedShape(String)
        case osStatus(OSStatus)
    }

    /// Reads the full credential pair (token + expiry). Prefer this when you want to
    /// cache the token across calls so you don't have to re-prompt the user via the
    /// keychain ACL dialog every 90s.
    public static func readClaudeCredentials() throws -> KeychainCredentials {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { throw Failure.notFound }
        guard status == errSecSuccess else { throw Failure.osStatus(status) }
        guard let data = item as? Data else { throw Failure.unexpectedShape("not Data") }

        // Outer JSON: { "claudeAiOauth": <object or JSON-encoded string> }
        guard let outer = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw Failure.unexpectedShape("outer not JSON object")
        }
        let inner: [String: Any]
        if let dict = outer["claudeAiOauth"] as? [String: Any] {
            inner = dict
        } else if let str = outer["claudeAiOauth"] as? String,
                  let strData = str.data(using: .utf8),
                  let parsed = try? JSONSerialization.jsonObject(with: strData) as? [String: Any] {
            inner = parsed
        } else {
            throw Failure.unexpectedShape("inner claudeAiOauth blob")
        }
        guard let token = inner["accessToken"] as? String, !token.isEmpty else {
            throw Failure.unexpectedShape("accessToken missing")
        }
        return KeychainCredentials(accessToken: token, expiresAt: parseExpiresAt(inner["expiresAt"]))
    }

    /// Convenience that drops the expiry — kept so existing call sites keep compiling.
    public static func readClaudeAccessToken() throws -> String {
        return try readClaudeCredentials().accessToken
    }

    /// Claude Code stores expiresAt in a few flavors across versions; accept all of them.
    private static func parseExpiresAt(_ raw: Any?) -> Date? {
        guard let raw else { return nil }
        // Heuristic: a number > 10^12 is milliseconds, smaller is seconds.
        if let ms = raw as? Double {
            return Date(timeIntervalSince1970: ms > 1_000_000_000_000 ? ms / 1000 : ms)
        }
        if let n = raw as? Int {
            return parseExpiresAt(Double(n))
        }
        if let s = raw as? String {
            if let d = Double(s) { return parseExpiresAt(d) }
            let f = ISO8601DateFormatter()
            f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let d = f.date(from: s) { return d }
            let p = ISO8601DateFormatter()
            p.formatOptions = [.withInternetDateTime]
            return p.date(from: s)
        }
        return nil
    }
}
