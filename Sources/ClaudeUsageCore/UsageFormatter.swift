import Foundation

public enum UsageFormatter {
    /// 1234 → "1.2K", 1_234_567 → "1.2M". Friendly for tight speech bubbles.
    public static func compact(_ n: Int) -> String {
        let value = Double(n)
        switch value {
        case 1_000_000_000...:
            return String(format: "%.1fB", value / 1_000_000_000)
        case 1_000_000...:
            return String(format: "%.1fM", value / 1_000_000)
        case 1_000...:
            return String(format: "%.1fK", value / 1_000)
        default:
            return "\(n)"
        }
    }

    public static func usd(_ amount: Double) -> String {
        if amount < 0.01 { return "<$0.01" }
        if amount < 1 { return String(format: "$%.2f", amount) }
        if amount < 100 { return String(format: "$%.2f", amount) }
        return String(format: "$%.0f", amount)
    }
}
