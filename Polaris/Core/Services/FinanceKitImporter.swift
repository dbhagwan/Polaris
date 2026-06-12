import Foundation
import SwiftData
#if canImport(FinanceKit)
import FinanceKit

/// Imports Apple Card / Apple Cash / Savings activity straight from Wallet —
/// fully on-device, no Plaid, no backend. Requires Apple's FinanceKit
/// entitlement (com.apple.developer.financekit, granted on request), so every
/// path here degrades to a clear status instead of crashing without it.
@MainActor
final class FinanceKitImporter {
    enum ImportResult {
        case unavailable          // device/region without Wallet financial data
        case denied               // user declined, or entitlement missing
        case imported(transactions: Int, accounts: Int)
    }

    var isSupported: Bool {
        FinanceStore.isDataAvailable(.financialData)
    }

    func importAll(into context: ModelContext, pipeline: AIPipeline) async -> ImportResult {
        guard isSupported else { return .unavailable }
        do {
            let status = try await FinanceStore.shared.requestAuthorization()
            guard status == .authorized else { return .denied }

            let fkAccounts = try await FinanceStore.shared.accounts(query: AccountQuery())
            let existingAccounts = (try? context.fetch(FetchDescriptor<Account>())) ?? []
            var accountIDsByFK: [String: UUID] = [:]
            var newAccounts = 0

            for fkAccount in fkAccounts {
                let providerID = "wallet-\(fkAccount.id.uuidString)"
                if let existing = existingAccounts.first(where: { $0.providerAccountID == providerID }) {
                    accountIDsByFK[fkAccount.id.uuidString] = existing.id
                    continue
                }
                let isLiability = fkAccount.liabilityAccount != nil
                let account = Account(
                    providerAccountID: providerID,
                    institutionName: fkAccount.institutionName,
                    name: fkAccount.displayName,
                    kind: isLiability ? .creditCard : .savings,
                    subtype: isLiability ? "credit card" : "savings",
                    mask: "",
                    currentBalance: 0,
                    currencyCode: fkAccount.currencyCode
                )
                context.insert(account)
                accountIDsByFK[fkAccount.id.uuidString] = account.id
                newAccounts += 1
            }

            let fkTransactions = try await FinanceStore.shared.transactions(query: TransactionQuery())
            let knownIDs = Set(((try? context.fetch(FetchDescriptor<Transaction>())) ?? []).map(\.providerTransactionID))
            var imported = 0

            for fkTransaction in fkTransactions {
                let providerID = "wallet-\(fkTransaction.id.uuidString)"
                guard !knownIDs.contains(providerID),
                      let accountID = accountIDsByFK[fkTransaction.accountID.uuidString] else { continue }
                // FinanceKit: credits are positive; Polaris uses Plaid's
                // convention (positive = money out), so flip on credit type.
                let rawAmount = fkTransaction.transactionAmount.amount
                let amount = fkTransaction.creditDebitIndicator == .credit ? -rawAmount : rawAmount
                let descriptor = fkTransaction.merchantName ?? fkTransaction.transactionDescription
                let categorization = await pipeline.categorization.categorize(
                    merchant: descriptor,
                    rawDescription: fkTransaction.transactionDescription,
                    amount: amount,
                    date: fkTransaction.transactionDate,
                    providerCategoryHint: nil
                )
                let transaction = Transaction(
                    providerTransactionID: providerID,
                    accountID: accountID,
                    amount: amount,
                    date: fkTransaction.transactionDate,
                    merchantName: descriptor,
                    rawDescription: fkTransaction.transactionDescription,
                    normalizedDescription: CategorizationEngine.normalizeMerchant(descriptor),
                    category: categorization.category,
                    subcategory: categorization.subcategory,
                    categorySource: categorization.source,
                    categoryConfidence: categorization.confidence,
                    isEssential: categorization.isEssential
                )
                transaction.needsAIReview = categorization.confidence < 0.65
                context.insert(transaction)
                imported += 1
            }

            try? context.save()
            await pipeline.recompute(in: context)
            return .imported(transactions: imported, accounts: newAccounts)
        } catch {
            // Most likely the FinanceKit entitlement isn't on this build.
            return .denied
        }
    }
}
#endif
