#if canImport(ActivityKit)
import ActivityKit
import Foundation

/// Live Activity payload: today's remaining allowance, glanceable in the
/// Dynamic Island and on the Lock Screen, updated by the pipeline after
/// every recompute. Shared between the app (start/update) and the widget
/// extension (render).
struct SafeToSpendActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var remainingToday: Decimal
        var todayAllowance: Decimal
        var currencyCode: String
        /// Spend pace vs. ideal − 1 (0.08 = 8% over).
        var paceDelta: Double
    }

    var startedAt: Date
}
#endif
