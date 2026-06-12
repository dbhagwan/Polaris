import Foundation

/// Envelope-style smoothing: remembers each day's base allowance so that
/// whatever yesterday left unspent can roll into today (the engine clamps
/// the credit). UserDefaults-backed, pruned to a week.
enum RolloverLedger {
    private static let key = "safeToSpend.dailyAllowances"

    private static var dayFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }

    /// Store today's base allowance (excluding any rollover credit, so a
    /// good streak compounds from real allowance, not from itself).
    static func record(allowance: Decimal, on date: Date = .now) {
        var ledger = (UserDefaults.standard.dictionary(forKey: key) as? [String: Double]) ?? [:]
        ledger[dayFormatter.string(from: date)] = allowance.doubleValue
        // Prune anything older than a week.
        if let cutoff = Calendar.current.date(byAdding: .day, value: -7, to: date) {
            let cutoffKey = dayFormatter.string(from: cutoff)
            ledger = ledger.filter { $0.key >= cutoffKey }
        }
        UserDefaults.standard.set(ledger, forKey: key)
    }

    /// Yesterday's allowance minus yesterday's discretionary spend, floored
    /// at zero. Returns 0 when there's no recorded history.
    static func unspentCredit(transactions: [Transaction], asOf now: Date = .now) -> Decimal {
        guard let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: now) else { return 0 }
        let ledger = (UserDefaults.standard.dictionary(forKey: key) as? [String: Double]) ?? [:]
        guard let recorded = ledger[dayFormatter.string(from: yesterday)] else { return 0 }
        let spent = transactions
            .filter { $0.countsAsDiscretionarySpend && Calendar.current.isDate($0.date, inSameDayAs: yesterday) }
            .reduce(Decimal(0)) { $0 + $1.amount }
        return max(0, Decimal(recorded) - spent)
    }
}
