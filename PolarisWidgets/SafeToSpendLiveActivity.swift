import ActivityKit
import SwiftUI
import WidgetKit

/// Lock Screen banner + Dynamic Island for today's remaining allowance.
struct SafeToSpendLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: SafeToSpendActivityAttributes.self) { context in
            // Lock Screen / banner presentation.
            HStack(spacing: 12) {
                Image(systemName: "sparkles")
                    .font(.title3)
                    .foregroundStyle(.mint)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Safe to spend today")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(context.state.remainingToday.widgetCurrency(context.state.currencyCode))
                        .font(.title2.bold())
                        .fontDesign(.rounded)
                        .monospacedDigit()
                        .privacySensitive()
                }
                Spacer()
                paceBadge(context.state.paceDelta)
            }
            .padding(14)
            .activityBackgroundTint(Color.black.opacity(0.6))
            .activitySystemActionForegroundColor(.mint)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: "sparkles")
                        .font(.title3)
                        .foregroundStyle(.mint)
                        .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(spacing: 2) {
                        Text("Safe to spend today")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(context.state.remainingToday.widgetCurrency(context.state.currencyCode))
                            .font(.title2.bold())
                            .fontDesign(.rounded)
                            .monospacedDigit()
                            .privacySensitive()
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    paceBadge(context.state.paceDelta)
                        .padding(.trailing, 4)
                }
            } compactLeading: {
                Image(systemName: "sparkles")
                    .foregroundStyle(.mint)
            } compactTrailing: {
                Text(context.state.remainingToday.widgetCurrency(context.state.currencyCode))
                    .font(.caption.bold())
                    .fontDesign(.rounded)
                    .monospacedDigit()
                    .foregroundStyle(.mint)
                    .privacySensitive()
            } minimal: {
                Image(systemName: "sparkles")
                    .foregroundStyle(.mint)
            }
        }
    }

    private func paceBadge(_ delta: Double) -> some View {
        Text(delta > 0.05 ? "over pace" : delta < -0.05 ? "under pace" : "on pace")
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                (delta > 0.05 ? Color.red : delta < -0.05 ? Color.green : Color.gray).opacity(0.25),
                in: Capsule()
            )
    }
}
