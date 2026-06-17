import XCTest
@testable import Polaris

/// Logic tests for the deterministic debt-payoff simulator. Pure value types,
/// no SwiftData — fast and reliable, independent of the UI screenshot suite.
final class DebtPayoffEngineTests: XCTestCase {

    private func debt(_ name: String, _ balance: Decimal, _ apr: Decimal, _ min: Decimal) -> DebtPayoffEngine.Debt {
        DebtPayoffEngine.Debt(name: name, balance: balance, aprPercent: apr, minimumPayment: min)
    }

    func testNoDebtIsTriviallyProjectable() {
        let p = DebtPayoffEngine.project(debts: [], strategy: .avalanche, monthlyExtra: 0)
        XCTAssertTrue(p.isProjectable)
        XCTAssertEqual(p.monthsToDebtFree, 0)
        XCTAssertEqual(p.totalInterest, 0)
        XCTAssertTrue(p.order.isEmpty)
    }

    func testZeroInterestPaysOffInExactMonths() {
        let p = DebtPayoffEngine.project(
            debts: [debt("Card", 1000, 0, 100)],
            strategy: .avalanche,
            monthlyExtra: 0
        )
        XCTAssertTrue(p.isProjectable)
        XCTAssertEqual(p.monthsToDebtFree, 10)
        XCTAssertEqual(p.totalInterest, 0)
    }

    func testAvalancheTargetsHighestAPRFirst() {
        let high = debt("High", 1000, 25, 25)
        let low = debt("Low", 1000, 5, 25)
        let p = DebtPayoffEngine.project(debts: [high, low], strategy: .avalanche, monthlyExtra: 200)

        XCTAssertTrue(p.isProjectable)
        XCTAssertEqual(p.order.first?.id, high.id, "Highest-APR debt should clear first under avalanche")

        let highPay = p.firstMonthAllocations.first { $0.id == high.id }?.payment ?? 0
        let lowPay = p.firstMonthAllocations.first { $0.id == low.id }?.payment ?? 0
        XCTAssertGreaterThan(highPay, lowPay, "Extra payment should land on the highest-APR debt")
    }

    func testSnowballTargetsSmallestBalanceFirst() {
        let small = debt("Small", 500, 5, 25)
        let big = debt("Big", 2000, 25, 25)

        let snowball = DebtPayoffEngine.project(debts: [small, big], strategy: .snowball, monthlyExtra: 200)
        XCTAssertEqual(snowball.order.first?.id, small.id, "Smallest balance clears first under snowball")

        let avalanche = DebtPayoffEngine.project(debts: [small, big], strategy: .avalanche, monthlyExtra: 200)
        XCTAssertEqual(avalanche.order.first?.id, big.id, "Highest APR clears first under avalanche")
    }

    func testExtraPaymentSavesTimeAndInterest() {
        let card = debt("Card", 5000, 20, 100)
        let withExtra = DebtPayoffEngine.project(debts: [card], strategy: .avalanche, monthlyExtra: 300)
        let minOnly = DebtPayoffEngine.project(debts: [card], strategy: .avalanche, monthlyExtra: 0)

        XCTAssertTrue(withExtra.isProjectable)
        XCTAssertTrue(minOnly.isProjectable)
        XCTAssertLessThan(withExtra.monthsToDebtFree, minOnly.monthsToDebtFree)
        XCTAssertLessThan(withExtra.totalInterest, minOnly.totalInterest)
        XCTAssertGreaterThan(withExtra.interestSavedVsMinimum, 0)
        XCTAssertEqual(withExtra.monthsSavedVsMinimum, minOnly.monthsToDebtFree - withExtra.monthsToDebtFree)
    }

    func testNotProjectableWhenMinimumBelowInterest() {
        // $200/mo interest, $50/mo minimum, no extra → the balance only grows.
        let p = DebtPayoffEngine.project(
            debts: [debt("Underwater", 10000, 24, 50)],
            strategy: .avalanche,
            monthlyExtra: 0
        )
        XCTAssertFalse(p.isProjectable)
    }

    func testPortfolioStrategiesDifferAndAvalancheIsInterestOptimal() {
        let debts = [
            debt("Store", 740, 18.99, 25),
            debt("Amex", 1624.55, 24.99, 40),
            debt("Auto", 12800, 6.49, 320),
        ]
        let avalanche = DebtPayoffEngine.project(debts: debts, strategy: .avalanche, monthlyExtra: 200)
        let snowball = DebtPayoffEngine.project(debts: debts, strategy: .snowball, monthlyExtra: 200)

        XCTAssertTrue(avalanche.isProjectable)
        XCTAssertTrue(snowball.isProjectable)
        XCTAssertEqual(avalanche.order.first?.name, "Amex", "Avalanche targets the highest APR")
        XCTAssertEqual(snowball.order.first?.name, "Store", "Snowball targets the smallest balance")
        XCTAssertLessThanOrEqual(avalanche.totalInterest, snowball.totalInterest, "Avalanche minimizes interest")
        XCTAssertEqual(avalanche.order.count, 3)
    }
}
