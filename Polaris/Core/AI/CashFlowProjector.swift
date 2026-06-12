import Foundation

/// Projects liquid balance day by day: starts from checking + savings,
/// drains the profile's variable daily spend, subtracts each recurring bill
/// on its expected date, and adds paychecks on the observed cadence. Pure
/// arithmetic over data the pipeline already produces — the low point is the
/// overdraft guard.
enum CashFlowProjector {
    struct DayProjection: Identifiable, Sendable {
        var date: Date
        var projectedBalance: Decimal
        var bills: [SpendForecast.UpcomingCharge] = []
        var paycheck: Decimal?
        var id: Date { date }
    }

    static func project(
        days: Int = 30,
        accounts: [Account],
        forecast: SpendForecast,
        profile: SpendingProfile,
        series: [RecurringDetector.RecurringSeries],
        asOf now: Date = .now
    ) -> [DayProjection] {
        let calendar = Calendar.current
        let start = now.startOfDay
        guard let end = calendar.date(byAdding: .day, value: days, to: start) else { return [] }

        var balance = accounts
            .filter { !$0.isHidden && ($0.kind == .checking || $0.kind == .savings) }
            .reduce(Decimal(0)) { $0 + ($1.availableBalance ?? $1.currentBalance) }
        let dailyVariable = max(0, profile.averageMonthlySpend - profile.fixedMonthlySpend) / 30

        // Expand each recurring series into every due date inside the window.
        var billsByDay: [Date: [SpendForecast.UpcomingCharge]] = [:]
        for entry in series {
            var next = entry.nextExpectedDate
            var guardrail = 0
            while next.startOfDay < end && guardrail < 64 {
                if next.startOfDay >= start {
                    billsByDay[next.startOfDay, default: []].append(.init(
                        merchant: entry.merchant,
                        amount: entry.averageAmount,
                        expectedDate: next,
                        category: entry.category,
                        isDiscretionary: entry.isDiscretionary
                    ))
                }
                next = calendar.date(byAdding: .day, value: max(1, entry.cadenceDays), to: next) ?? end
                guardrail += 1
            }
        }

        // Paychecks repeat from the forecast's next expected one (biweekly).
        var paydays: [Date: Decimal] = [:]
        if let firstPay = forecast.expectedNextPaycheckDate,
           let amount = forecast.expectedNextPaycheckAmount {
            var pay = firstPay
            var guardrail = 0
            while pay.startOfDay < end && guardrail < 16 {
                if pay.startOfDay >= start { paydays[pay.startOfDay] = amount }
                pay = calendar.date(byAdding: .day, value: 14, to: pay) ?? end
                guardrail += 1
            }
        }

        return (0..<days).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: start) else { return nil }
            if offset > 0 { balance -= dailyVariable }
            for bill in billsByDay[day] ?? [] { balance -= bill.amount }
            if let pay = paydays[day] { balance += pay }
            return DayProjection(
                date: day,
                projectedBalance: balance,
                bills: billsByDay[day] ?? [],
                paycheck: paydays[day]
            )
        }
    }

    /// The window's minimum — the number the calendar exists to surface.
    static func lowPoint(of projections: [DayProjection]) -> DayProjection? {
        projections.min { $0.projectedBalance < $1.projectedBalance }
    }
}
