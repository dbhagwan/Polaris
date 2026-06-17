import Foundation

// `DebtStrategy` lives in Core/Models (shared with the watch/widget targets,
// which compile `UserProfile`). The engine below is app-only.

/// Deterministic debt-payoff simulator. Pure value types in, pure projection
/// out — no SwiftData, no I/O — so it's fully unit-testable. Mirrors how
/// `SafeToSpendEngine` is a free function over plain inputs.
///
/// Model: every active debt pays its minimum each month; whatever's left of the
/// monthly pool (sum of minimums + the user's extra) is thrown at the priority
/// debt, and freed-up minimums roll forward as debts clear (the "snowball
/// roll"). Interest accrues monthly at APR/12 on the running balance.
enum DebtPayoffEngine {
    /// One liability fed into the simulation.
    struct Debt: Identifiable, Sendable, Equatable {
        var id: UUID
        var name: String
        var balance: Decimal
        /// Annual percentage rate as a percentage number, e.g. 19.99 = 19.99%.
        var aprPercent: Decimal
        var minimumPayment: Decimal

        init(id: UUID = UUID(), name: String, balance: Decimal, aprPercent: Decimal, minimumPayment: Decimal) {
            self.id = id
            self.name = name
            self.balance = balance
            self.aprPercent = aprPercent
            self.minimumPayment = minimumPayment
        }
    }

    /// When a specific debt clears, and how much interest it cost on the way.
    struct PayoffStep: Identifiable, Sendable, Equatable {
        var id: UUID
        var name: String
        var payoffMonth: Int
        var interestPaid: Decimal
    }

    /// How a single month's payment splits across debts (for "this month" UI).
    struct Allocation: Identifiable, Sendable, Equatable {
        var id: UUID
        var name: String
        var payment: Decimal
    }

    struct Projection: Sendable, Equatable {
        var monthsToDebtFree: Int
        var payoffDate: Date
        var totalInterest: Decimal
        var totalPaid: Decimal
        /// Debts in the order they clear.
        var order: [PayoffStep]
        var monthlyExtra: Decimal
        /// Interest avoided versus paying minimums only (extra = 0).
        var interestSavedVsMinimum: Decimal
        /// Months saved versus paying minimums only.
        var monthsSavedVsMinimum: Int
        /// False when minimums + extra can't outrun interest (never pays off).
        var isProjectable: Bool
        /// This month's payment split across debts, largest first.
        var firstMonthAllocations: [Allocation]
    }

    static func project(
        debts: [Debt],
        strategy: DebtStrategy,
        monthlyExtra: Decimal,
        asOf now: Date = .now
    ) -> Projection {
        let active = debts.filter { $0.balance > 0 }
        guard !active.isEmpty else {
            return Projection(
                monthsToDebtFree: 0, payoffDate: now, totalInterest: 0, totalPaid: 0,
                order: [], monthlyExtra: monthlyExtra, interestSavedVsMinimum: 0,
                monthsSavedVsMinimum: 0, isProjectable: true, firstMonthAllocations: []
            )
        }

        let plan = simulate(active, strategy: strategy, monthlyExtra: max(0, monthlyExtra))
        let baseline = simulate(active, strategy: strategy, monthlyExtra: 0)

        let payoffDate = Calendar.current.date(byAdding: .month, value: plan.months, to: now) ?? now
        let order = active
            .compactMap { debt -> PayoffStep? in
                guard let step = plan.payoff[debt.id] else { return nil }
                return PayoffStep(id: debt.id, name: debt.name, payoffMonth: step.month, interestPaid: step.interest)
            }
            .sorted { $0.payoffMonth < $1.payoffMonth }

        let bothProjectable = plan.projectable && baseline.projectable
        let interestSaved = bothProjectable ? max(0, baseline.totalInterest - plan.totalInterest) : 0
        let monthsSaved = bothProjectable ? max(0, baseline.months - plan.months) : 0

        let allocations = active
            .compactMap { debt -> Allocation? in
                guard let pay = plan.firstMonth[debt.id], pay > 0 else { return nil }
                return Allocation(id: debt.id, name: debt.name, payment: pay)
            }
            .sorted { $0.payment > $1.payment }

        return Projection(
            monthsToDebtFree: plan.months,
            payoffDate: payoffDate,
            totalInterest: plan.totalInterest,
            totalPaid: plan.totalPaid,
            order: order,
            monthlyExtra: monthlyExtra,
            interestSavedVsMinimum: interestSaved,
            monthsSavedVsMinimum: monthsSaved,
            isProjectable: plan.projectable,
            firstMonthAllocations: allocations
        )
    }

    // MARK: - Simulation

    private struct SimResult {
        var months: Int
        var totalInterest: Decimal
        var totalPaid: Decimal
        var payoff: [UUID: (month: Int, interest: Decimal)]
        var projectable: Bool
        var firstMonth: [UUID: Decimal]
    }

    private static let maxMonths = 1200 // 100 years — a hard stop for non-converging debts.

    private static func simulate(
        _ debts: [Debt],
        strategy: DebtStrategy,
        monthlyExtra: Decimal
    ) -> SimResult {
        var balances = Dictionary(uniqueKeysWithValues: debts.map { ($0.id, $0.balance) })
        var interestByDebt = Dictionary(uniqueKeysWithValues: debts.map { ($0.id, Decimal(0)) })
        let minByID = Dictionary(uniqueKeysWithValues: debts.map { ($0.id, $0.minimumPayment) })
        let aprByID = Dictionary(uniqueKeysWithValues: debts.map { ($0.id, $0.aprPercent) })
        let ids = debts.map(\.id)

        let pool = debts.reduce(Decimal(0)) { $0 + $1.minimumPayment } + monthlyExtra
        var payoffMonth: [UUID: Int] = [:]
        var totalInterest = Decimal(0)
        var totalPaid = Decimal(0)
        var firstMonth: [UUID: Decimal] = [:]

        func priorityOrder() -> [UUID] {
            let active = ids.filter { (balances[$0] ?? 0) > 0 }
            switch strategy {
            case .avalanche:
                return active.sorted {
                    let a = aprByID[$0] ?? 0, b = aprByID[$1] ?? 0
                    if a != b { return a > b }
                    return (balances[$0] ?? 0) < (balances[$1] ?? 0)
                }
            case .snowball:
                return active.sorted { (balances[$0] ?? 0) < (balances[$1] ?? 0) }
            }
        }

        var month = 0
        while month < maxMonths {
            let activeBefore = ids.filter { (balances[$0] ?? 0) > 0 }
            if activeBefore.isEmpty { break }
            month += 1
            let totalBefore = activeBefore.reduce(Decimal(0)) { $0 + (balances[$1] ?? 0) }

            // 1. Accrue interest on the running balance.
            for id in activeBefore {
                let monthlyRate = (aprByID[id] ?? 0) / 100 / 12
                let interest = roundedToCents((balances[id] ?? 0) * monthlyRate)
                if interest > 0 {
                    balances[id, default: 0] += interest
                    interestByDebt[id, default: 0] += interest
                    totalInterest += interest
                }
            }

            var available = pool
            // 2. Pay the minimum on every active debt.
            for id in activeBefore where available > 0 {
                let pay = min(min(minByID[id] ?? 0, balances[id] ?? 0), available)
                if pay > 0 {
                    balances[id, default: 0] -= pay
                    available -= pay
                    totalPaid += pay
                    if month == 1 { firstMonth[id, default: 0] += pay }
                }
            }
            // 3. Throw the remainder at the priority order.
            for id in priorityOrder() where available > 0 {
                let pay = min(available, balances[id] ?? 0)
                if pay > 0 {
                    balances[id, default: 0] -= pay
                    available -= pay
                    totalPaid += pay
                    if month == 1 { firstMonth[id, default: 0] += pay }
                }
            }
            // 4. Round and record any debt that cleared this month.
            for id in activeBefore {
                let rounded = roundedToCents(balances[id] ?? 0)
                balances[id] = rounded <= 0 ? 0 : rounded
                if (balances[id] ?? 0) <= 0 && payoffMonth[id] == nil {
                    payoffMonth[id] = month
                }
            }
            // 5. No progress means minimums + extra can't cover interest.
            let totalAfter = ids.reduce(Decimal(0)) { $0 + max(0, balances[$1] ?? 0) }
            if totalAfter >= totalBefore {
                return SimResult(
                    months: month, totalInterest: totalInterest, totalPaid: totalPaid,
                    payoff: payoffDict(payoffMonth, interestByDebt), projectable: false, firstMonth: firstMonth
                )
            }
        }

        let allPaid = ids.allSatisfy { (balances[$0] ?? 0) <= 0 }
        let months = payoffMonth.values.max() ?? month
        return SimResult(
            months: allPaid ? months : month,
            totalInterest: totalInterest,
            totalPaid: totalPaid,
            payoff: payoffDict(payoffMonth, interestByDebt),
            projectable: allPaid,
            firstMonth: firstMonth
        )
    }

    private static func payoffDict(
        _ payoffMonth: [UUID: Int],
        _ interestByDebt: [UUID: Decimal]
    ) -> [UUID: (month: Int, interest: Decimal)] {
        var result: [UUID: (month: Int, interest: Decimal)] = [:]
        for (id, month) in payoffMonth {
            result[id] = (month, interestByDebt[id] ?? 0)
        }
        return result
    }

    private static func roundedToCents(_ value: Decimal) -> Decimal {
        var result = Decimal()
        var input = value
        NSDecimalRound(&result, &input, 2, .plain)
        return result
    }
}
