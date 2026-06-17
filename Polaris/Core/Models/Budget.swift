import Foundation
import SwiftData

@Model
final class Budget {
    var id: UUID = UUID()
    /// Total monthly budget across all spend categories.
    var monthlyTotal: Decimal = 0
    /// Day of month the budget period starts (1–28).
    var periodStartDay: Int = 1
    var currencyCode: String = "USD"
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now

    @Relationship(deleteRule: .cascade, inverse: \BudgetCategory.budget)
    var categories: [BudgetCategory] = []

    init(
        id: UUID = UUID(),
        monthlyTotal: Decimal,
        periodStartDay: Int = 1,
        currencyCode: String = "USD",
        createdAt: Date = .now
    ) {
        self.id = id
        self.monthlyTotal = monthlyTotal
        self.periodStartDay = periodStartDay
        self.currencyCode = currencyCode
        self.createdAt = createdAt
        self.updatedAt = createdAt
    }

    func limit(for category: SpendingCategory) -> Decimal? {
        categories.first { $0.category == category }?.monthlyLimit
    }

    /// Current budget period containing `date`, respecting the custom start day.
    func period(containing date: Date = .now, calendar: Calendar = .current) -> DateInterval {
        var components = calendar.dateComponents([.year, .month], from: date)
        components.day = periodStartDay
        var start = calendar.date(from: components) ?? date
        if start > date {
            start = calendar.date(byAdding: .month, value: -1, to: start) ?? start
        }
        let end = calendar.date(byAdding: .month, value: 1, to: start) ?? start
        return DateInterval(start: start, end: end)
    }
}

@Model
final class BudgetCategory {
    var id: UUID = UUID()
    var categoryRaw: String = "miscellaneous"
    var monthlyLimit: Decimal = 0
    /// True if this limit came from the AI recommendation rather than manual entry.
    var isAIRecommended: Bool = false

    var budget: Budget?

    var category: SpendingCategory {
        get { SpendingCategory(rawValue: categoryRaw) ?? .miscellaneous }
        set { categoryRaw = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        category: SpendingCategory,
        monthlyLimit: Decimal,
        isAIRecommended: Bool = false
    ) {
        self.id = id
        self.categoryRaw = category.rawValue
        self.monthlyLimit = monthlyLimit
        self.isAIRecommended = isAIRecommended
    }
}

@Model
final class UserProfile {
    var id: UUID = UUID()
    var appleUserID: String?
    var displayName: String = ""
    var currencyCode: String = "USD"
    var privacyModeEnabled: Bool = false
    var appLockEnabled: Bool = false
    /// Categories the user excluded from safe-to-spend, as raw values.
    var excludedSafeToSpendCategories: [String] = []
    var onboardingCompleted: Bool = false
    var createdAt: Date = Date.now
    /// Debt-payoff plan: strategy and the extra payment (beyond minimums) the
    /// user commits per month. The extra reserves from safe-to-spend.
    var debtStrategyRaw: String = "avalanche"
    var debtMonthlyExtra: Decimal = 0

    var debtStrategy: DebtStrategy {
        get { DebtStrategy(rawValue: debtStrategyRaw) ?? .avalanche }
        set { debtStrategyRaw = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        appleUserID: String? = nil,
        displayName: String = "",
        currencyCode: String = "USD",
        privacyModeEnabled: Bool = false,
        appLockEnabled: Bool = false,
        excludedSafeToSpendCategories: [String] = [],
        onboardingCompleted: Bool = false,
        createdAt: Date = .now,
        debtStrategy: DebtStrategy = .avalanche,
        debtMonthlyExtra: Decimal = 0
    ) {
        self.id = id
        self.appleUserID = appleUserID
        self.displayName = displayName
        self.currencyCode = currencyCode
        self.privacyModeEnabled = privacyModeEnabled
        self.appLockEnabled = appLockEnabled
        self.excludedSafeToSpendCategories = excludedSafeToSpendCategories
        self.onboardingCompleted = onboardingCompleted
        self.createdAt = createdAt
        self.debtStrategyRaw = debtStrategy.rawValue
        self.debtMonthlyExtra = debtMonthlyExtra
    }
}

@Model
final class NetWorthSnapshot {
    var id: UUID = UUID()
    var date: Date = Date.now
    var totalAssets: Decimal = 0
    var totalLiabilities: Decimal = 0

    var netWorth: Decimal { totalAssets - totalLiabilities }

    init(id: UUID = UUID(), date: Date, totalAssets: Decimal, totalLiabilities: Decimal) {
        self.id = id
        self.date = date
        self.totalAssets = totalAssets
        self.totalLiabilities = totalLiabilities
    }
}
