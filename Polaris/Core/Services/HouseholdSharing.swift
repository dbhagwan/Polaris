import CloudKit
import Foundation
import SwiftUI
import UIKit

/// Household budgeting, scoped v1: the budget is mirrored into a CloudKit
/// record in a custom zone and shared via CKShare, so a partner sees one
/// number. SwiftData's CloudKit mirror can't share records itself, hence the
/// parallel record.
///
/// TODO(production): handle share acceptance in-app (CKSharingSupported +
/// scene delegate) and merge participant edits back into the local budget.
@MainActor
final class HouseholdSharing {
    static let shared = HouseholdSharing()

    private let container = CKContainer(identifier: ModelContainerFactory.cloudKitContainerID)
    private let zoneID = CKRecordZone.ID(zoneName: "Household", ownerName: CKCurrentUserDefaultName)
    private let recordName = "household-budget"

    /// Mirrors the budget into the shared zone and returns the share to
    /// present. Reuses an existing share when one is already active.
    func shareBudget(_ budget: Budget) async throws -> CKShare {
        let database = container.privateCloudDatabase
        _ = try? await database.save(CKRecordZone(zoneID: zoneID))

        let recordID = CKRecord.ID(recordName: recordName, zoneID: zoneID)
        let record: CKRecord
        if let existing = try? await database.record(for: recordID) {
            record = existing
        } else {
            record = CKRecord(recordType: "HouseholdBudget", recordID: recordID)
        }
        record["monthlyTotal"] = (budget.monthlyTotal as NSDecimalNumber).doubleValue
        record["periodStartDay"] = budget.periodStartDay
        record["currencyCode"] = budget.currencyCode
        record["updatedAt"] = Date.now

        if let shareReference = record.share,
           let existingShare = try? await database.record(for: shareReference.recordID) as? CKShare {
            _ = try await database.modifyRecords(saving: [record], deleting: [])
            return existingShare
        }

        let share = CKShare(rootRecord: record)
        share[CKShare.SystemFieldKey.title] = "Household budget"
        share.publicPermission = .none
        _ = try await database.modifyRecords(saving: [record, share], deleting: [])
        return share
    }

    var ckContainer: CKContainer { container }
}

/// Thin wrapper around the system share sheet for CloudKit shares.
struct CloudSharingView: UIViewControllerRepresentable {
    let share: CKShare
    let container: CKContainer

    func makeUIViewController(context: Context) -> UICloudSharingController {
        UICloudSharingController(share: share, container: container)
    }

    func updateUIViewController(_ controller: UICloudSharingController, context: Context) {}
}
