import Foundation

/// Personal price index: tracks the same receipt line item across repeat
/// purchases and measures how its price moved. Only possible because the
/// receipt pipeline captures items — no other source has this.
enum PriceIndexEngine {
    struct Mover: Identifiable, Sendable {
        var name: String
        var firstPrice: Decimal
        var latestPrice: Decimal
        var firstDate: Date
        var latestDate: Date
        var id: String { name }

        var change: Double {
            guard firstPrice > 0 else { return 0 }
            return ((latestPrice - firstPrice) / firstPrice).doubleValue
        }
    }

    struct Index: Sendable {
        /// Weighted average price change across repeat-purchased items.
        var overallChange: Double
        var movers: [Mover]
        var itemsTracked: Int
    }

    static func build(from receipts: [Receipt]) -> Index? {
        // Unit price per normalized item name, over time.
        var observations: [String: [(date: Date, price: Decimal)]] = [:]
        for receipt in receipts {
            let date = receipt.purchaseDate ?? receipt.capturedAt
            for item in receipt.lineItems where item.price > 0 {
                let unit = item.price / Decimal(max(1, item.quantity))
                observations[Self.normalize(item.name), default: []].append((date, unit))
            }
        }

        var movers: [Mover] = []
        for (name, points) in observations where points.count >= 2 {
            let sorted = points.sorted { $0.date < $1.date }
            guard let first = sorted.first, let latest = sorted.last,
                  latest.date.timeIntervalSince(first.date) >= 86_400 * 14 else { continue }
            movers.append(Mover(
                name: name.capitalized,
                firstPrice: first.price,
                latestPrice: latest.price,
                firstDate: first.date,
                latestDate: latest.date
            ))
        }
        guard !movers.isEmpty else { return nil }

        let totalWeight = movers.reduce(0.0) { $0 + $1.latestPrice.doubleValue }
        let overall = totalWeight > 0
            ? movers.reduce(0.0) { $0 + $1.change * $1.latestPrice.doubleValue } / totalWeight
            : 0
        return Index(
            overallChange: overall,
            movers: movers.sorted { abs($0.change) > abs($1.change) },
            itemsTracked: movers.count
        )
    }

    private static func normalize(_ name: String) -> String {
        name.lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"\s+\d+(pk|ct|oz|lb)$"#, with: "", options: .regularExpression)
    }
}
