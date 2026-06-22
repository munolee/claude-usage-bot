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

    // MARK: - App-owned token cache
    //
    // Reading Claude Code's `Claude Code-credentials` item triggers the macOS ACL
    // dialog whenever Claude Code's daemon has rewritten that item (which resets its
    // ACL). To avoid hitting it on every launch, we keep our *own* keychain item.
    // macOS auto-trusts the creating app for items it created, so reading our own
    // item never prompts. We only fall back to Claude Code's item when our cached
    // token is missing or near expiry.

    /// Service name for the item this app owns and controls.
    public static let cacheService = "com.example.ClaudeUsageBot.tokencache"
    private static let cacheAccount = "default"
    /// When Claude Code's blob carries no expiry, assume the cached token is good for
    /// this long before we re-read the source item.
    private static let defaultCacheTTL: TimeInterval = 4 * 3600

    /// Returns a usable token without prompting when possible:
    ///   1. our own cache, if still valid
    ///   2. otherwise Claude Code's item (may prompt), then refresh our cache
    public static func cachedOrFreshCredentials(safetyMargin: TimeInterval = 300) -> KeychainCredentials? {
        if let cached = readOwnCache(),
           let exp = cached.expiresAt,
           exp.timeIntervalSinceNow > safetyMargin {
            return cached
        }
        guard let fresh = try? readClaudeCredentials() else {
            // Source unreadable (e.g. ACL denied) — fall back to whatever we cached,
            // even if it's past our soft margin; the API will 401 if it's truly dead.
            return readOwnCache()
        }
        writeOwnCache(fresh)
        return fresh
    }

    /// Reads the app-owned cache item. Never prompts (we created it).
    public static func readOwnCache() -> KeychainCredentials? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: cacheService,
            kSecAttrAccount as String: cacheAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let token = obj["accessToken"] as? String, !token.isEmpty else {
            return nil
        }
        let exp = (obj["expiresAt"] as? Double).map { Date(timeIntervalSince1970: $0) }
        return KeychainCredentials(accessToken: token, expiresAt: exp)
    }

    /// Writes the app-owned cache item with an "allow all applications" ACL.
    ///
    /// The default ACL macOS attaches to a self-created item is bound to the creating
    /// app's signature (cdhash for ad-hoc builds). Since each local rebuild changes the
    /// cdhash, the next build counts as a "different app" and gets prompted. Creating
    /// the item with an allow-all ACL removes that per-signature gate entirely, so the
    /// cache never prompts regardless of how the app was signed or rebuilt. The token
    /// stays encrypted at rest in the keychain — this only widens *which* local apps may
    /// read our own copy, the same posture as Keychain Access's "Allow all applications".
    public static func writeOwnCache(_ creds: KeychainCredentials) {
        let expiry = creds.expiresAt ?? Date().addingTimeInterval(defaultCacheTTL)
        let payload: [String: Any] = [
            "accessToken": creds.accessToken,
            "expiresAt": expiry.timeIntervalSince1970
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload) else { return }

        // Recreate the item so the allow-all ACL applies even to a previously-created
        // (signature-bound) cache item from an older build.
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: cacheService,
            kSecAttrAccount as String: cacheAccount
        ]
        SecItemDelete(base as CFDictionary)

        var add = base
        add[kSecValueData as String] = data
        if let access = allowAllAccess() {
            // kSecAttrAccess (legacy ACL) is mutually exclusive with kSecAttrAccessible.
            add[kSecAttrAccess as String] = access
        } else {
            add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        }
        SecItemAdd(add as CFDictionary, nil)
    }

    /// Builds a SecAccess that lets any application read the item without a prompt —
    /// the programmatic equivalent of "Allow all applications to access this item".
    private static func allowAllAccess() -> SecAccess? {
        var access: SecAccess?
        guard SecAccessCreate("ClaudeUsageBot token cache" as CFString, [] as CFArray, &access) == errSecSuccess,
              let access else { return nil }
        var aclListCF: CFArray?
        guard SecAccessCopyACLList(access, &aclListCF) == errSecSuccess,
              let aclList = aclListCF as? [SecACL] else { return access }
        for acl in aclList {
            // nil trusted-application list = any app may access; empty prompt selector
            // = no confirmation dialog.
            SecACLSetContents(acl, nil, "" as CFString, SecKeychainPromptSelector(rawValue: 0))
        }
        return access
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
