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
public enum KeychainTokenReader {
    public static let service = "Claude Code-credentials"

    public enum Failure: Swift.Error, Equatable {
        case notFound
        case unexpectedShape(String)
        case osStatus(OSStatus)
    }

    public static func readClaudeAccessToken() throws -> String {
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
        return token
    }
}
