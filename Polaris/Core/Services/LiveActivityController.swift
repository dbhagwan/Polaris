import ActivityKit
import Foundation

/// Starts/updates/ends the safe-to-spend Live Activity. Driven by the
/// pipeline after each recompute, gated on the Settings toggle.
@MainActor
enum LiveActivityController {
    static let enabledKey = "liveActivityEnabled"

    static func sync(
        decision: SafeToSpendDecision?,
        spentTodayDiscretionary: Decimal,
        paceDelta: Double,
        currencyCode: String
    ) async {
        let enabled = UserDefaults.standard.bool(forKey: enabledKey)
        guard enabled,
              ActivityAuthorizationInfo().areActivitiesEnabled,
              let decision else {
            await endAll()
            return
        }

        let state = SafeToSpendActivityAttributes.ContentState(
            remainingToday: max(0, decision.todayAllowance - spentTodayDiscretionary),
            todayAllowance: decision.todayAllowance,
            currencyCode: currencyCode,
            paceDelta: paceDelta
        )
        let content = ActivityContent(state: state, staleDate: Calendar.current.date(byAdding: .hour, value: 6, to: .now))

        if let activity = Activity<SafeToSpendActivityAttributes>.activities.first {
            await activity.update(content)
        } else {
            _ = try? Activity.request(
                attributes: SafeToSpendActivityAttributes(startedAt: .now),
                content: content
            )
        }
    }

    static func endAll() async {
        for activity in Activity<SafeToSpendActivityAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }
}
