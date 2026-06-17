import Foundation

/// Debt-payoff strategy. Both order the *extra* payment; minimums are always
/// paid on every debt first.
///
/// Lives in Core/Models (not Core/AI) because `UserProfile` stores it and that
/// model is shared with the watch and widget targets, which don't compile the
/// app-only `DebtPayoffEngine`.
enum DebtStrategy: String, Codable, CaseIterable, Sendable {
    /// Highest APR first — mathematically minimizes total interest.
    case avalanche
    /// Smallest balance first — fastest visible wins, best for momentum.
    case snowball

    var displayName: String {
        switch self {
        case .avalanche: "Avalanche"
        case .snowball: "Snowball"
        }
    }

    var detail: String {
        switch self {
        case .avalanche: "Targets the highest interest rate first — pays the least interest overall."
        case .snowball: "Clears the smallest balance first — quick wins to keep momentum."
        }
    }
}
