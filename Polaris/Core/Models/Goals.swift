import Foundation
import SwiftData

/// A savings goal funded out of the daily allowance: each active goal
/// reserves `dailyReservation` from safe-to-spend so progress is automatic
/// pace, not leftover wishes.
@Model
final class SavingsGoal {
    var id: UUID = UUID()
    var name: String = ""
    var emoji: String = "🎯"
    var targetAmount: Decimal = 0
    var fundedAmount: Decimal = 0
    /// Optional deadline; without one the reservation assumes a gentle 90 days.
    var targetDate: Date?
    var createdAt: Date = Date.now

    var isCompleted: Bool { fundedAmount >= targetAmount && targetAmount > 0 }

    var progress: Double {
        guard targetAmount > 0 else { return 0 }
        return min(1, (fundedAmount / targetAmount).doubleValue)
    }

    /// What this goal asks of each day's allowance to stay on pace.
    func dailyReservation(asOf now: Date = .now) -> Decimal {
        let remaining = max(0, targetAmount - fundedAmount)
        guard remaining > 0 else { return 0 }
        let days: Int
        if let targetDate, targetDate > now {
            days = max(1, now.daysUntil(targetDate))
        } else {
            days = 90
        }
        return remaining / Decimal(days)
    }

    init(
        id: UUID = UUID(),
        name: String,
        emoji: String = "🎯",
        targetAmount: Decimal,
        fundedAmount: Decimal = 0,
        targetDate: Date? = nil,
        createdAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.emoji = emoji
        self.targetAmount = targetAmount
        self.fundedAmount = fundedAmount
        self.targetDate = targetDate
        self.createdAt = createdAt
    }
}

/// A user-authored categorization rule: substring match on the normalized
/// descriptor. Sits between correction memory and the built-in rules, so the
/// user's own rules always beat heuristics and the model.
@Model
final class UserRule {
    var id: UUID = UUID()
    /// Case-insensitive substring matched against the normalized descriptor.
    var pattern: String = ""
    var categoryRaw: String = "miscellaneous"
    var markEssential: Bool = false
    var isEnabled: Bool = true
    var createdAt: Date = Date.now

    var category: SpendingCategory {
        get { SpendingCategory(rawValue: categoryRaw) ?? .miscellaneous }
        set { categoryRaw = newValue.rawValue }
    }

    func matches(_ text: String) -> Bool {
        isEnabled && !pattern.isEmpty && text.localizedCaseInsensitiveContains(pattern)
    }

    init(
        id: UUID = UUID(),
        pattern: String,
        category: SpendingCategory,
        markEssential: Bool = false,
        isEnabled: Bool = true,
        createdAt: Date = .now
    ) {
        self.id = id
        self.pattern = pattern
        self.categoryRaw = category.rawValue
        self.markEssential = markEssential
        self.isEnabled = isEnabled
        self.createdAt = createdAt
    }
}

/// One position inside an investment account (Plaid investments holdings).
@Model
final class Holding {
    var id: UUID = UUID()
    var providerHoldingID: String = ""
    var accountID: UUID = UUID()
    var symbol: String = ""
    var name: String = ""
    var quantity: Decimal = 0
    var price: Decimal = 0
    var value: Decimal = 0
    var costBasis: Decimal?
    var updatedAt: Date = Date.now

    var gain: Decimal? { costBasis.map { value - $0 } }

    init(
        id: UUID = UUID(),
        providerHoldingID: String,
        accountID: UUID,
        symbol: String,
        name: String,
        quantity: Decimal,
        price: Decimal,
        value: Decimal,
        costBasis: Decimal? = nil
    ) {
        self.id = id
        self.providerHoldingID = providerHoldingID
        self.accountID = accountID
        self.symbol = symbol
        self.name = name
        self.quantity = quantity
        self.price = price
        self.value = value
        self.costBasis = costBasis
        self.updatedAt = .now
    }
}
