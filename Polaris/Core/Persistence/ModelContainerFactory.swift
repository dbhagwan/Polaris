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
    ]) }

    static let cloudKitContainerID = "iCloud.com.polaris.app"

    static func make(inMemory: Bool = false) -> ModelContainer {
        // CloudKit-backed store: the private database syncs budgets, settings,
        // accounts, transactions, and receipts across the user's devices
        // automatically. Falls back to a local-only store when iCloud is
        // unavailable (no account signed in, simulators/CI without the
        // entitlement) — the app keeps working, just without sync.
        if !inMemory {
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
