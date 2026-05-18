import Foundation

public struct UsageTotals: Equatable, Sendable {
    public var inputTokens: Int = 0
    public var outputTokens: Int = 0
    public var cacheCreationInputTokens: Int = 0
    public var cacheReadInputTokens: Int = 0
    public var estimatedCostUSD: Double = 0
    public var messageCount: Int = 0

    public var totalTokens: Int {
        inputTokens + outputTokens + cacheCreationInputTokens + cacheReadInputTokens
    }
}

public struct UsageSummary: Equatable, Sendable {
    public let today: UsageTotals
    public let last7Days: UsageTotals
    public let allTime: UsageTotals
    public let perModelToday: [String: UsageTotals]
    public let latestActivity: Date?
    public let generatedAt: Date

    public init(
        today: UsageTotals,
        last7Days: UsageTotals,
        allTime: UsageTotals,
        perModelToday: [String: UsageTotals],
        latestActivity: Date?,
        generatedAt: Date
    ) {
        self.today = today
        self.last7Days = last7Days
        self.allTime = allTime
        self.perModelToday = perModelToday
        self.latestActivity = latestActivity
        self.generatedAt = generatedAt
    }
}

public enum UsageAggregator {
    /// Builds a summary from a flat list of records. Dedupes by messageId so re-reading the same
    /// transcript files doesn't double-count.
    public static func summarize(
        records: [UsageRecord],
        now: Date = Date(),
        calendar: Calendar = .autoupdatingCurrent
    ) -> UsageSummary {
        var seen = Set<String>()
        var deduped: [UsageRecord] = []
        deduped.reserveCapacity(records.count)
        for r in records where seen.insert(r.messageId).inserted {
            deduped.append(r)
        }

        let startOfToday = calendar.startOfDay(for: now)
        let startOfWeek = calendar.date(byAdding: .day, value: -6, to: startOfToday) ?? startOfToday

        var today = UsageTotals()
        var week = UsageTotals()
        var all = UsageTotals()
        var perModel: [String: UsageTotals] = [:]
        var latest: Date?

        for r in deduped {
            add(r, into: &all)
            if r.timestamp >= startOfWeek {
                add(r, into: &week)
            }
            if r.timestamp >= startOfToday {
                add(r, into: &today)
                var slot = perModel[r.model, default: UsageTotals()]
                add(r, into: &slot)
                perModel[r.model] = slot
            }
            if let l = latest {
                if r.timestamp > l { latest = r.timestamp }
            } else {
                latest = r.timestamp
            }
        }

        return UsageSummary(
            today: today,
            last7Days: week,
            allTime: all,
            perModelToday: perModel,
            latestActivity: latest,
            generatedAt: now
        )
    }

    private static func add(_ r: UsageRecord, into totals: inout UsageTotals) {
        totals.inputTokens += r.inputTokens
        totals.outputTokens += r.outputTokens
        totals.cacheCreationInputTokens += r.cacheCreationInputTokens
        totals.cacheReadInputTokens += r.cacheReadInputTokens
        totals.messageCount += 1
        if let cost = Pricing.cost(of: r) {
            totals.estimatedCostUSD += cost
        }
    }
}
