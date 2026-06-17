import SwiftData
import SwiftUI

/// The AI command center: safe-to-spend hero, pace, alerts, budget health,
/// receipt matches, upcoming bills, net worth and cash flow at a glance.
struct HomeView: View {
    @Environment(AppEnvironment.self) private var appEnvironment
    @Environment(\.modelContext) private var modelContext
    @Environment(\.horizontalSizeClass) private var sizeClass

    @Query(sort: \NetWorthSnapshot.date, order: .reverse) private var netWorthSnapshots: [NetWorthSnapshot]
    @Query private var accounts: [Account]
    @Query(sort: \Receipt.capturedAt, order: .reverse) private var receipts: [Receipt]
    @Query private var transactions: [Transaction]
    @Query(sort: \SavingsGoal.createdAt) private var goals: [SavingsGoal]
    @Query private var profiles: [UserProfile]

    @State private var showExplanation = false
    @State private var showMonthlyStory = false
    @Namespace private var zoomNamespace

    private var pipeline: AIPipeline { appEnvironment.pipeline }
    private var isLoading: Bool {
        if case .syncing = appEnvironment.syncState { return pipeline.lastRunAt == nil }
        return false
    }

    var body: some View {
        ScrollView {
            if isLoading {
                loadingSkeleton
            } else if accounts.isEmpty {
                EmptyStateView(
                    systemImage: "building.columns",
                    title: "No accounts yet",
                    message: "Connect a bank account and Polaris starts learning your spending immediately."
                )
            } else {
                content
            }
        }
        .background(AppBackground())
        .toolbar {
            // iPad reaches Settings via the sidebar; iPhone gets it here.
            if sizeClass == .compact {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        SettingsView()
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("Settings")
                }
            }
        }
        .refreshable { await appEnvironment.sync(context: modelContext) }
        .sensoryFeedback(.impact(weight: .light), trigger: showExplanation)
        .sheet(isPresented: $showExplanation) {
            if let decision = pipeline.safeToSpend {
                SafeToSpendExplanationView(decision: decision)
                    .presentationDetents([.medium, .large])
            }
        }
    }

    private var content: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: sizeClass == .regular ? 360 : 600), spacing: Theme.sectionSpacing)],
            spacing: Theme.sectionSpacing
        ) {
            if let decision = pipeline.safeToSpend {
                SafeToSpendCard(decision: decision) { showExplanation = true }
            }
            if let forecast = pipeline.forecast, let risk = pipeline.risk {
                SpendPaceCard(forecast: forecast, risk: risk)
            }
            if !dailySpend.isEmpty {
                DailySpendCard(days: dailySpend)
            }
            if !pipeline.recommendations.isEmpty {
                RecommendationsCard(recommendations: pipeline.recommendations)
            }
            if let forecast = pipeline.forecast, !forecast.upcomingRecurringCharges.isEmpty {
                UpcomingBillsCard(charges: Array(forecast.upcomingRecurringCharges.prefix(4)))
            }
            goalsCard
            debtCard
            recentReceiptsCard
            netWorthCard
            if let forecast = pipeline.forecast {
                NavigationLink {
                    CashFlowCalendarView()
                } label: {
                    CashFlowCard(forecast: forecast)
                }
                .buttonStyle(.plain)
            }
            monthlyStoryCard
            if !pipeline.insights.isEmpty {
                InsightsCard(insights: Array(pipeline.insights.prefix(3)))
            }
        }
        // Cards drift in and fade as they scroll — part of the alive feel.
        .scrollTransition(.interactive) { content, phase in
            content
                .opacity(phase.isIdentity ? 1 : 0.85)
                .scaleEffect(phase.isIdentity ? 1 : 0.98)
        }
        .padding()
    }

    private var loadingSkeleton: some View {
        VStack(spacing: Theme.sectionSpacing) {
            SkeletonBlock(height: 160)
            SkeletonBlock(height: 90)
            SkeletonBlock(height: 120)
            SkeletonBlock(height: 90)
        }
        .padding()
    }

    /// Every calendar day of the last two weeks (zero-filled so quiet days
    /// still draw), spend only.
    private var dailySpend: [DailySpendChart.Day] {
        let calendar = Calendar.current
        let start = calendar.date(byAdding: .day, value: -13, to: Date.now.startOfDay) ?? .now
        var totals: [Date: Decimal] = [:]
        for offset in 0...13 {
            if let day = calendar.date(byAdding: .day, value: offset, to: start) {
                totals[day] = 0
            }
        }
        for transaction in transactions where transaction.countsAsSpend && transaction.date >= start {
            totals[transaction.date.startOfDay, default: 0] += transaction.amount
        }
        return totals.map { DailySpendChart.Day(date: $0.key, total: $0.value) }
            .sorted { $0.date < $1.date }
    }

    /// Tapping opens the full Net Worth view — front and center, not buried
    /// in Settings. Zooms out of the card (iOS 18+ zoom transition).
    private var netWorthCard: some View {
        NavigationLink {
            NetWorthView()
                .navigationTransition(.zoom(sourceID: "netWorth", in: zoomNamespace))
        } label: {
            Card(title: "Net Worth", systemImage: "chart.line.uptrend.xyaxis") {
                let netWorth = accounts.reduce(Decimal(0)) { $0 + $1.netWorthContribution }
                HStack(alignment: .firstTextBaseline) {
                    AmountText(amount: netWorth, font: .title2, showCents: false)
                    Spacer()
                    if let change = netWorthChange30Days {
                        Label(change.currencyCompact(), systemImage: change >= 0 ? "arrow.up.right" : "arrow.down.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(change >= 0 ? Theme.positive : Theme.negative)
                    }
                }
                HStack {
                    Text("\(accounts.filter { !$0.isHidden }.count) accounts")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .buttonStyle(.plain)
        .matchedTransitionSource(id: "netWorth", in: zoomNamespace)
    }

    /// Goal rings, or an invitation to set one. Pushes the full Goals screen.
    private var goalsCard: some View {
        NavigationLink {
            GoalsView()
        } label: {
            Card(title: "Goals", systemImage: "flag.checkered") {
                if goals.isEmpty {
                    Text("Reserve a slice of each day's allowance toward something you want.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    HStack(spacing: 18) {
                        ForEach(goals.prefix(3)) { goal in
                            VStack(spacing: 5) {
                                ZStack {
                                    ProgressRing(progress: goal.progress, lineWidth: 5, size: 46)
                                    Text(goal.emoji).font(.subheadline)
                                }
                                Text(goal.name)
                                    .font(.caption2)
                                    .lineLimit(1)
                            }
                        }
                        Spacer()
                    }
                }
                HStack {
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var liabilities: [Account] {
        accounts.filter { $0.kind.isLiability && !$0.isClosed && $0.currentBalance > 0 }
    }

    /// Quick payoff projection from the user's current strategy + extra payment.
    private var debtProjection: DebtPayoffEngine.Projection {
        let profile = profiles.first
        let debts = liabilities.map { account in
            DebtPayoffEngine.Debt(
                id: account.id,
                name: account.name,
                balance: account.currentBalance,
                aprPercent: account.apr ?? 0,
                minimumPayment: account.minimumPayment ?? DebtView.defaultMinimum(for: account.currentBalance)
            )
        }
        return DebtPayoffEngine.project(
            debts: debts,
            strategy: profile?.debtStrategy ?? .avalanche,
            monthlyExtra: profile?.debtMonthlyExtra ?? 0
        )
    }

    /// Shown only when the user carries a balance. Pushes the full planner.
    @ViewBuilder
    private var debtCard: some View {
        if !liabilities.isEmpty {
            NavigationLink {
                DebtView()
            } label: {
                Card(title: "Debt Payoff", systemImage: "creditcard") {
                    let total = liabilities.reduce(Decimal(0)) { $0 + $1.currentBalance }
                    HStack(alignment: .firstTextBaseline) {
                        AmountText(amount: total, font: .title2, showCents: false)
                        Spacer()
                        if debtProjection.isProjectable, debtProjection.monthsToDebtFree > 0 {
                            Label(
                                "Debt-free \(debtProjection.payoffDate.formatted(.dateTime.month(.abbreviated).year()))",
                                systemImage: "flag.checkered"
                            )
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.positive)
                        }
                    }
                    HStack {
                        Text("\(liabilities.count) \(liabilities.count == 1 ? "liability" : "liabilities")")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .buttonStyle(.plain)
        }
    }

    private var monthlyStoryCard: some View {
        Card {
            Button {
                showMonthlyStory = true
            } label: {
                HStack {
                    Image(systemName: "sparkles.tv")
                        .font(.title3)
                        .foregroundStyle(Theme.heroGradient)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Your \(Date.now.formatted(.dateTime.month(.wide))) story")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                        Text("A swipeable recap of the month — shareable.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
            }
            .buttonStyle(.plain)
        }
        .fullScreenCover(isPresented: $showMonthlyStory) {
            MonthlyStoryView()
        }
    }

    private var netWorthChange30Days: Decimal? {
        guard let latest = netWorthSnapshots.first else { return nil }
        let thirtyDaysAgo = Calendar.current.date(byAdding: .day, value: -30, to: .now) ?? .now
        guard let old = netWorthSnapshots.first(where: { $0.date <= thirtyDaysAgo }) else { return nil }
        return latest.netWorth - old.netWorth
    }

    /// Tapping opens the full Receipts screen — Receipts gave up its tab to
    /// Net Worth, so this card is its front door on iPhone.
    private var recentReceiptsCard: some View {
        NavigationLink {
            ReceiptsView()
        } label: {
            Card(title: "Receipts", systemImage: "doc.text.viewfinder") {
                let recent = Array(receipts.prefix(3))
                if recent.isEmpty {
                    Text("Scan a receipt and Polaris matches it to the card charge automatically.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(recent) { receipt in
                        HStack {
                            Image(systemName: receipt.matchStatus == .unmatched ? "questionmark.circle" : "checkmark.circle.fill")
                                .foregroundStyle(receipt.matchStatus == .unmatched ? Theme.warning : Theme.positive)
                            VStack(alignment: .leading) {
                                Text(receipt.merchant ?? "Unknown merchant").font(.subheadline.weight(.medium))
                                Text(receipt.matchStatus.displayName).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if let total = receipt.total {
                                AmountText(amount: total, font: .subheadline)
                            }
                        }
                    }
                }
                HStack {
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    NavigationStack { HomeView() }
        .environment(AppEnvironment.mock())
        .modelContainer(ModelContainerFactory.preview())
}
