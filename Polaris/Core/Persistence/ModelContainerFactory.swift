import Foundation
import SwiftData

enum ModelContainerFactory {
    // Computed because Schema is not Sendable (Swift 6 strict concurrency).
    static var schema: Schema { Schema([
        UserProfile.self,
        LinkedInstitution.self,
        Account.self,
        Transaction.self,
        Receipt.self,
        Budget.self,
        BudgetCategory.self,
        NetWorthSnapshot.self,
        SavingsGoal.self,
        UserRule.self,
        Holding.self,
    ]) }

    static let cloudKitContainerID = "iCloud.com.dbhagwan.polaris"

    static func make(inMemory: Bool = false) -> ModelContainer {
        // CloudKit-backed store: the private database syncs budgets, settings,
        // accounts, transactions, and receipts across the user's devices
        // automatically. Only attempted when an iCloud account is actually
        // signed in — otherwise (simulators/CI, signed-out devices) the
        // CloudKit machinery retries setup forever and keeps the main run
        // loop busy, so we go straight to the local store.
        let iCloudAvailable = FileManager.default.ubiquityIdentityToken != nil
        if !inMemory && iCloudAvailable {
            let cloud = ModelConfiguration(
                schema: schema,
                cloudKitDatabase: .private(cloudKitContainerID)
            )
            if let container = try? ModelContainer(for: schema, configurations: [cloud]) {
                return container
            }
        }
        let local = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: inMemory,
            cloudKitDatabase: .none
        )
        do {
            return try ModelContainer(for: schema, configurations: [local])
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }

    /// In-memory container pre-seeded with sample data for previews and UI development.
    @MainActor
    static func preview() -> ModelContainer {
        let container = make(inMemory: true)
        SampleData.seed(into: container.mainContext)
        return container
    }
}
