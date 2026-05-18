import Foundation

/// One 5-hour Claude Code usage window. Starts at the first message of the session
/// and expires exactly `SessionDetector.length` later, regardless of subsequent activity.
public struct SessionWindow: Equatable, Sendable {
    public let startedAt: Date
    public let expiresAt: Date
    public let usageUSD: Double
    public let tokens: Int
    public let messageCount: Int

    public init(startedAt: Date, expiresAt: Date, usageUSD: Double, tokens: Int, messageCount: Int) {
        self.startedAt = startedAt
        self.expiresAt = expiresAt
        self.usageUSD = usageUSD
        self.tokens = tokens
        self.messageCount = messageCount
    }

    public func remaining(from now: Date) -> TimeInterval {
        max(0, expiresAt.timeIntervalSince(now))
    }

    public func isActive(at now: Date) -> Bool {
        now < expiresAt
    }

    /// 0...1, clamped. Uses cost when a budget is provided.
    public func usageFraction(budgetUSD: Double) -> Double {
        guard budgetUSD > 0 else { return 0 }
        return min(1, max(0, usageUSD / budgetUSD))
    }
}

public enum SessionDetector {
    /// Claude Code's rolling usage window length.
    public static let length: TimeInterval = 5 * 3600

    /// Returns the most recent session window if it is still active at `now`. A new session starts
    /// whenever a message arrives after the previous session's `expiresAt`.
    public static func currentSession(records: [UsageRecord], now: Date = Date()) -> SessionWindow? {
        let sessions = sessions(from: records)
        guard let last = sessions.last, last.isActive(at: now) else { return nil }
        return last
    }

    /// All sessions found in the records, oldest first. Useful for history views or testing.
    public static func sessions(from records: [UsageRecord]) -> [SessionWindow] {
        // Dedupe and sort.
        var seen = Set<String>()
        let unique = records.filter { seen.insert($0.messageId).inserted }
        let sorted = unique.sorted { $0.timestamp < $1.timestamp }

        struct Acc {
            var start: Date
            var expires: Date
            var cost: Double
            var tokens: Int
            var count: Int
        }
        var acc: [Acc] = []
        for r in sorted {
            if var last = acc.last, r.timestamp < last.expires {
                last.cost += Pricing.cost(of: r) ?? 0
                last.tokens += r.totalTokens
                last.count += 1
                acc[acc.count - 1] = last
            } else {
                acc.append(Acc(
                    start: r.timestamp,
                    expires: r.timestamp.addingTimeInterval(length),
                    cost: Pricing.cost(of: r) ?? 0,
                    tokens: r.totalTokens,
                    count: 1
                ))
            }
        }
        return acc.map {
            SessionWindow(
                startedAt: $0.start,
                expiresAt: $0.expires,
                usageUSD: $0.cost,
                tokens: $0.tokens,
                messageCount: $0.count
            )
        }
    }
}
