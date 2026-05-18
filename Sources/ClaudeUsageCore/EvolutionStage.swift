import Foundation

/// Six progressive forms the mascot cycles through as session usage rises.
public enum EvolutionStage: String, CaseIterable, Sendable {
    case egg
    case baby
    case growth
    case mature
    case perfect
    case ultimate

    /// Korean display name (for menus, tooltips, etc).
    public var label: String {
        switch self {
        case .egg: return "알"
        case .baby: return "유년기"
        case .growth: return "성장기"
        case .mature: return "성숙기"
        case .perfect: return "완전체"
        case .ultimate: return "궁극체"
        }
    }

    /// Picks the stage matching a session's `usageFraction`. With no session — or a
    /// session that has produced no priced cost yet — the mascot stays in egg form.
    public static func stage(forFraction fraction: Double, hasActiveSession: Bool) -> EvolutionStage {
        guard hasActiveSession, fraction > 0 else { return .egg }
        switch fraction {
        case ..<0.20: return .baby
        case ..<0.50: return .growth
        case ..<0.80: return .mature
        case ..<1.00: return .perfect
        default:      return .ultimate
        }
    }
}
