import SwiftData
import SwiftUI

/// Wrapped-style monthly recap: swipeable full-screen glass cards, every
/// number deterministic from the user's data, shareable as an image.
struct MonthlyStoryView: View {
    @Environment(AppEnvironment.self) private var appEnvironment
    @Environment(\.dismiss) private var dismiss
    @Query private var transactions: [Transaction]

    private var monthName: String {
        Date.now.formatted(.dateTime.month(.wide))
    }

    private var monthTransactions: [Transaction] {
        let calendar = Calendar.current
        return transactions.filter {
            calendar.isDate($0.date, equalTo: .now, toGranularity: .month) && $0.countsAsSpend
        }
    }

    private var totalSpent: Decimal {
        monthTransactions.reduce(0) { $0 + $1.amount }
    }

    private var topCategory: (category: SpendingCategory, total: Decimal)? {
        Dictionary(grouping: monthTransactions, by: \.category)
            .map { ($0.key, $0.value.reduce(Decimal(0)) { $0 + $1.amount }) }
            .max { $0.1 < $1.1 }
    }

    private var biggestPurchase: Transaction? {
        monthTransactions.max { $0.amount < $1.amount }
    }

    var body: some View {
        TabView {
            page(
                caption: "\(monthName) so far",
                emoji: "💸",
                amount: totalSpent,
                detail: "across \(monthTransactions.count) purchases"
            )
            if let topCategory {
                page(
                    caption: "Where it went",
                    emoji: nil,
                    systemImage: topCategory.category.systemImage,
                    tint: topCategory.category.chartColor,
                    amount: topCategory.total,
                    title: topCategory.category.displayName,
                    detail: totalSpent > 0
                        ? "\((topCategory.total / totalSpent).doubleValue.percentString) of the month"
                        : ""
                )
            }
            if let biggestPurchase {
                page(
                    caption: "Biggest single purchase",
                    emoji: "🏷️",
                    amount: biggestPurchase.amount,
                    title: biggestPurchase.normalizedDescription,
                    detail: biggestPurchase.date.shortDay
                )
            }
            if let profile = appEnvironment.pipeline.profile {
                page(
                    caption: "Subscriptions",
                    emoji: "🔁",
                    amount: profile.subscriptionMonthlyLoad,
                    detail: "per month, every month"
                )
                if profile.savingsRate > 0 {
                    page(
                        caption: "Kept, not spent",
                        emoji: "🌱",
                        amount: nil,
                        title: profile.savingsRate.percentString,
                        detail: "of income saved this period"
                    )
                }
            }
            sharePage
        }
        .tabViewStyle(.page)
        .indexViewStyle(.page(backgroundDisplayMode: .always))
        .background(AppBackground())
        .overlay(alignment: .topTrailing) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.subheadline.weight(.semibold))
                    .padding(10)
            }
            .buttonStyle(.glass)
            .accessibilityLabel("Close")
            .padding()
        }
    }

    private func page(
        caption: String,
        emoji: String?,
        systemImage: String? = nil,
        tint: Color = Theme.accent,
        amount: Decimal?,
        title: String? = nil,
        detail: String
    ) -> some View {
        VStack(spacing: 14) {
            Spacer()
            if let emoji {
                Text(emoji).font(.system(size: 56))
            } else if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 48))
                    .foregroundStyle(tint)
            }
            Text(caption.uppercased())
                .font(.caption.weight(.semibold))
                .kerning(1)
                .foregroundStyle(.secondary)
            if let amount {
                AmountText(
                    amount: amount,
                    font: .system(size: 56, weight: .bold),
                    showCents: false,
                    style: AnyShapeStyle(Theme.heroGradient)
                )
            }
            if let title {
                Text(title)
                    .font(amount == nil ? .system(size: 56, weight: .bold) : .title2.weight(.semibold))
                    .multilineTextAlignment(.center)
            }
            Text(detail)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            Spacer()
        }
        .padding(32)
    }

    private var sharePage: some View {
        VStack(spacing: 18) {
            Spacer()
            shareCard
            ShareLink(
                item: renderShareImage(),
                preview: SharePreview("My \(monthName) in money", image: renderShareImage())
            ) {
                Label("Share your month", systemImage: "square.and.arrow.up")
                    .font(.subheadline.weight(.medium))
                    .padding(.horizontal, 6)
            }
            .buttonStyle(.glass)
            Spacer()
            Spacer()
        }
        .padding(32)
    }

    private var shareCard: some View {
        VStack(spacing: 10) {
            Text("\(monthName) in money".uppercased())
                .font(.caption.weight(.semibold))
                .kerning(1)
                .foregroundStyle(.secondary)
            AmountText(
                amount: totalSpent,
                font: .system(size: 44, weight: .bold),
                showCents: false,
                style: AnyShapeStyle(Theme.heroGradient)
            )
            if let topCategory {
                Text("Mostly \(topCategory.category.displayName.lowercased()) · tracked with Polaris")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(28)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    @MainActor
    private func renderShareImage() -> Image {
        let renderer = ImageRenderer(content: shareCard
            .environment(appEnvironment)
            .frame(width: 360)
            .padding(24)
            .background(Color.black)
        )
        renderer.scale = 3
        if let image = renderer.uiImage {
            return Image(uiImage: image)
        }
        return Image(systemName: "sparkles")
    }
}

#Preview {
    MonthlyStoryView()
        .environment(AppEnvironment.mock())
        .modelContainer(ModelContainerFactory.preview())
}
