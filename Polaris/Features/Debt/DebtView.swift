import SwiftData
import SwiftUI

/// Debt-payoff planner. Picks a strategy (avalanche/snowball), lets the user
/// commit an extra monthly payment, and shows the debt-free date, interest
/// cost, and what the extra payment saves. The extra payment reserves from
/// safe-to-spend, so deleveraging happens on pace — the mirror of Goals.
struct DebtView: View {
    @Environment(AppEnvironment.self) private var appEnvironment
    @Environment(\.modelContext) private var modelContext
    @Query private var accounts: [Account]
    @Query private var profiles: [UserProfile]

    @State private var editingAccount: Account?

    private var liabilities: [Account] {
        accounts
            .filter { $0.kind.isLiability && !$0.isClosed && $0.currentBalance > 0 }
            .sorted { $0.currentBalance > $1.currentBalance }
    }

    private var profile: UserProfile? { profiles.first }
    private var strategy: DebtStrategy { profile?.debtStrategy ?? .avalanche }
    private var extra: Decimal { profile?.debtMonthlyExtra ?? 0 }
    private var currencyCode: String { profile?.currencyCode ?? "USD" }

    private var totalDebt: Decimal {
        liabilities.reduce(Decimal(0)) { $0 + $1.currentBalance }
    }
    private var totalMinimums: Decimal {
        liabilities.reduce(Decimal(0)) { $0 + ($1.minimumPayment ?? Self.defaultMinimum(for: $1.currentBalance)) }
    }
    private var debts: [DebtPayoffEngine.Debt] {
        liabilities.map { account in
            DebtPayoffEngine.Debt(
                id: account.id,
                name: account.name,
                balance: account.currentBalance,
                aprPercent: account.apr ?? 0,
                minimumPayment: account.minimumPayment ?? Self.defaultMinimum(for: account.currentBalance)
            )
        }
    }
    private var projection: DebtPayoffEngine.Projection {
        DebtPayoffEngine.project(debts: debts, strategy: strategy, monthlyExtra: extra)
    }
    private var missingAPR: Bool { liabilities.contains { ($0.apr ?? 0) <= 0 } }

    var body: some View {
        ScrollView {
            if liabilities.isEmpty {
                EmptyStateView(
                    systemImage: "creditcard",
                    title: "No debt to plan",
                    message: "When you carry a balance on a credit card or loan, Polaris builds a payoff plan and reserves the extra payment from your daily allowance."
                )
                .padding(.top, 60)
            } else {
                VStack(spacing: Theme.sectionSpacing) {
                    summaryCard
                    strategyCard
                    extraPaymentCard
                    if !projection.order.isEmpty {
                        payoffOrderCard
                    }
                    debtsCard
                    if missingAPR {
                        missingAPRNote
                    }
                }
                .padding()
            }
        }
        .background(AppBackground())
        .navigationTitle("Debt")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editingAccount) { account in
            DebtAccountEditorView(account: account)
        }
    }

    // MARK: - Summary

    private var summaryCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                Text("TOTAL DEBT")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .kerning(0.6)
                AmountText(
                    amount: totalDebt,
                    font: .system(size: 44, weight: .bold),
                    showCents: false,
                    style: AnyShapeStyle(Theme.heroGradient)
                )
                Divider().padding(.vertical, 2)
                if projection.isProjectable {
                    HStack(spacing: 18) {
                        metric("Debt-free", projection.payoffDate.formatted(.dateTime.month(.abbreviated).year()))
                        metric("Time left", Self.durationText(months: projection.monthsToDebtFree))
                        metric("Interest", projection.totalInterest.currencyCompact(currencyCode))
                    }
                    if projection.monthlyExtra > 0 && projection.interestSavedVsMinimum > 0 {
                        Label {
                            Text("Your \(extra.currency(currencyCode, showCents: false))/mo extra saves \(projection.interestSavedVsMinimum.currency(currencyCode, showCents: false)) and \(Self.durationText(months: projection.monthsSavedVsMinimum)) versus minimums.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        } icon: {
                            Image(systemName: "sparkles").foregroundStyle(Theme.accent)
                        }
                        .padding(.top, 2)
                    }
                } else {
                    Label {
                        Text("Minimum payments don't outpace interest on these balances. Add an extra monthly payment below to start making progress.")
                            .font(.footnote)
                            .foregroundStyle(Theme.warning)
                    } icon: {
                        Image(systemName: "exclamationmark.triangle").foregroundStyle(Theme.warning)
                    }
                }
            }
        }
    }

    private func metric(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption2).foregroundStyle(.secondary)
            Text(value).font(.subheadline.weight(.semibold)).monospacedDigit()
        }
    }

    // MARK: - Strategy

    private var strategyCard: some View {
        Card(title: "Strategy", systemImage: "arrow.down.right.circle") {
            Picker("Strategy", selection: Binding(
                get: { strategy },
                set: { setStrategy($0) }
            )) {
                ForEach(DebtStrategy.allCases, id: \.self) { option in
                    Text(option.displayName).tag(option)
                }
            }
            .pickerStyle(.segmented)
            Text(strategy.detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Extra payment

    private var extraPaymentCard: some View {
        Card(title: "Extra monthly payment", systemImage: "plus.forwardslash.minus") {
            HStack {
                Text("Beyond the \(totalMinimums.currency(currencyCode, showCents: false)) minimums")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                AmountText(amount: extra, font: .headline, showCents: false)
            }
            Slider(
                value: Binding(
                    get: { extra.doubleValue },
                    set: { setExtra(Decimal($0)) }
                ),
                in: 0...max(500, totalMinimums.doubleValue * 3),
                step: 25
            )
            .tint(Theme.accent)
            Text("Reserved from your daily safe-to-spend — see “Why this number?” on Home.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .sensoryFeedback(.selection, trigger: extra)
    }

    // MARK: - Payoff order

    private var payoffOrderCard: some View {
        Card(title: "Payoff order", systemImage: "list.number") {
            ForEach(Array(projection.order.enumerated()), id: \.element.id) { index, step in
                HStack(spacing: 12) {
                    Text("\(index + 1)")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Theme.accent)
                        .frame(width: 22, height: 22)
                        .background(Theme.accent.opacity(0.15), in: Circle())
                    VStack(alignment: .leading, spacing: 2) {
                        Text(step.name).font(.subheadline.weight(.medium))
                        Text("Paid off \(Self.durationText(months: step.payoffMonth)) in · \(step.interestPaid.currency(currencyCode, showCents: false)) interest")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                if step.id != projection.order.last?.id {
                    Divider()
                }
            }
        }
    }

    // MARK: - Debts

    private var debtsCard: some View {
        Card(title: "Your liabilities", systemImage: "creditcard") {
            ForEach(liabilities) { account in
                Button {
                    editingAccount = account
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: account.kind == .loan ? "banknote" : "creditcard")
                            .foregroundStyle(.secondary)
                            .frame(width: 24)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(account.name).font(.subheadline.weight(.medium))
                            Text(aprMinSummary(account))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        AmountText(amount: account.currentBalance, font: .subheadline, showCents: false)
                        Image(systemName: "chevron.right")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                }
                .buttonStyle(.plain)
                if account.id != liabilities.last?.id {
                    Divider()
                }
            }
        }
    }

    private func aprMinSummary(_ account: Account) -> String {
        let apr = account.apr ?? 0
        let aprText = apr > 0 ? "\(apr.formatted(.number.precision(.fractionLength(0...2))))% APR" : "Set APR"
        let min = account.minimumPayment ?? Self.defaultMinimum(for: account.currentBalance)
        return "\(aprText) · \(min.currency(currencyCode, showCents: false))/mo min"
    }

    private var missingAPRNote: some View {
        Card {
            Label {
                Text("Some liabilities are missing an APR, so interest is estimated low. Tap a card above to set its rate for an accurate plan.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } icon: {
                Image(systemName: "info.circle").foregroundStyle(Theme.accent)
            }
        }
    }

    // MARK: - Mutations

    private func setStrategy(_ newValue: DebtStrategy) {
        let target = ensureProfile()
        target.debtStrategy = newValue
        persist()
    }

    private func setExtra(_ newValue: Decimal) {
        let target = ensureProfile()
        target.debtMonthlyExtra = max(0, newValue)
        persist()
    }

    @discardableResult
    private func ensureProfile() -> UserProfile {
        if let profile { return profile }
        let created = UserProfile()
        modelContext.insert(created)
        return created
    }

    private func persist() {
        try? modelContext.save()
        Task { await appEnvironment.pipeline.recompute(in: modelContext) }
    }

    // MARK: - Helpers

    /// Sensible default minimum when the user hasn't entered one: 2% of the
    /// balance, floored at $25 (the usual card minimum).
    static func defaultMinimum(for balance: Decimal) -> Decimal {
        max(25, (balance * Decimal(0.02)))
    }

    static func durationText(months: Int) -> String {
        guard months > 0 else { return "0 mo" }
        let years = months / 12
        let remainder = months % 12
        if years == 0 { return "\(remainder) mo" }
        if remainder == 0 { return "\(years) yr" }
        return "\(years) yr \(remainder) mo"
    }
}

/// Edits the APR and minimum payment for a liability account.
struct DebtAccountEditorView: View {
    @Bindable var account: Account

    @Environment(AppEnvironment.self) private var appEnvironment
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var apr: Double = 0
    @State private var minimum: Double = 0

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Balance", value: account.currentBalance.currency(account.currencyCode))
                } header: {
                    Text(account.name)
                }
                Section("Annual rate") {
                    HStack {
                        Text("APR")
                        Spacer()
                        TextField("0.00", value: $apr, format: .number.precision(.fractionLength(0...2)))
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 90)
                        Text("%").foregroundStyle(.secondary)
                    }
                }
                Section("Monthly minimum") {
                    HStack {
                        Text("Minimum payment")
                        Spacer()
                        TextField("0", value: $minimum, format: .number.precision(.fractionLength(0...2)))
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 90)
                    }
                }
            }
            .navigationTitle("Liability")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                }
            }
            .onAppear {
                apr = (account.apr ?? 0).doubleValue
                minimum = (account.minimumPayment ?? 0).doubleValue
            }
        }
    }

    private func save() {
        account.apr = apr > 0 ? Decimal(apr) : nil
        account.minimumPayment = minimum > 0 ? Decimal(minimum) : nil
        try? modelContext.save()
        Task { await appEnvironment.pipeline.recompute(in: modelContext) }
        dismiss()
    }
}

#Preview {
    NavigationStack { DebtView() }
        .environment(AppEnvironment.mock())
        .modelContainer(ModelContainerFactory.preview())
}
