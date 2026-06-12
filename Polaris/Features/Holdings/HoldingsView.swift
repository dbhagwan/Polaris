import SwiftData
import SwiftUI

/// Positions inside one investment account: allocation ring by holding,
/// per-position rows with gain/loss when cost basis is known.
struct HoldingsView: View {
    let account: Account

    @Query private var allHoldings: [Holding]

    private var holdings: [Holding] {
        allHoldings
            .filter { $0.accountID == account.id }
            .sorted { $0.value > $1.value }
    }

    private var totalValue: Decimal {
        holdings.reduce(0) { $0 + $1.value }
    }

    private var totalGain: Decimal? {
        let known = holdings.compactMap(\.gain)
        return known.isEmpty ? nil : known.reduce(0, +)
    }

    /// A stable hue per symbol, walked around the category palette.
    private func color(for index: Int) -> Color {
        let palette = SpendingCategory.allCases.map(\.chartColor)
        return palette[index % palette.count]
    }

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.sectionSpacing) {
                if holdings.isEmpty {
                    EmptyStateView(
                        systemImage: "chart.line.uptrend.xyaxis",
                        title: "No holdings yet",
                        message: "Positions appear after the next sync of this investment account."
                    )
                    .padding(.top, 60)
                } else {
                    allocationCard
                    positionsCard
                }
            }
            .padding()
        }
        .background(AppBackground())
        .navigationTitle(account.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var allocationCard: some View {
        Card(title: "Allocation", systemImage: "chart.pie.fill") {
            DonutChart(
                slices: holdings.enumerated().map { index, holding in
                    DonutSlice(
                        id: holding.providerHoldingID,
                        label: holding.symbol.isEmpty ? holding.name : holding.symbol,
                        amount: holding.value,
                        color: color(for: index)
                    )
                },
                centerCaption: "portfolio value",
                showsPercentLabels: true
            )
            .frame(height: 210)
            if let totalGain {
                HStack(spacing: 4) {
                    Image(systemName: totalGain >= 0 ? "arrow.up.right" : "arrow.down.right")
                    AmountText(amount: totalGain, font: .subheadline, colorBySign: true)
                    Text("vs. cost basis")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(totalGain >= 0 ? Theme.positive : Theme.negative)
            }
        }
    }

    private var positionsCard: some View {
        Card(title: "Positions", systemImage: "list.bullet") {
            ForEach(Array(holdings.enumerated()), id: \.element.id) { index, holding in
                HStack(spacing: 8) {
                    Circle().fill(color(for: index)).frame(width: 8, height: 8)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(holding.symbol.isEmpty ? holding.name : holding.symbol)
                            .font(.subheadline.weight(.medium))
                        Text("\(holding.quantity.doubleValue.formatted(.number.precision(.fractionLength(0...2)))) × \(holding.price.currency())")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 1) {
                        AmountText(amount: holding.value, font: .subheadline, showCents: false)
                        if totalValue > 0 {
                            Text((holding.value / totalValue).doubleValue.percentString)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }
}
