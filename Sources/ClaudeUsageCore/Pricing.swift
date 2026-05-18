import Foundation

/// Best-effort per-million-token pricing for cost estimation. Update as Anthropic publishes new rates.
/// Returns nil for unknown models — caller should treat that as "cost unknown" rather than zero.
public enum Pricing {
    public struct Rate: Sendable {
        public let inputPerMTok: Double
        public let outputPerMTok: Double
        public let cacheWritePerMTok: Double
        public let cacheReadPerMTok: Double
    }

    public static func rate(for model: String) -> Rate? {
        let normalized = model.lowercased()
        if normalized.contains("opus") {
            return Rate(inputPerMTok: 15, outputPerMTok: 75, cacheWritePerMTok: 18.75, cacheReadPerMTok: 1.5)
        }
        if normalized.contains("sonnet") {
            return Rate(inputPerMTok: 3, outputPerMTok: 15, cacheWritePerMTok: 3.75, cacheReadPerMTok: 0.3)
        }
        if normalized.contains("haiku") {
            return Rate(inputPerMTok: 1, outputPerMTok: 5, cacheWritePerMTok: 1.25, cacheReadPerMTok: 0.1)
        }
        return nil
    }

    /// Returns USD cost estimate, or nil if the model isn't priced.
    public static func cost(of record: UsageRecord) -> Double? {
        guard let r = rate(for: record.model) else { return nil }
        let m = 1_000_000.0
        return Double(record.inputTokens) / m * r.inputPerMTok
             + Double(record.outputTokens) / m * r.outputPerMTok
             + Double(record.cacheCreationInputTokens) / m * r.cacheWritePerMTok
             + Double(record.cacheReadInputTokens) / m * r.cacheReadPerMTok
    }
}
