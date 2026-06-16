import Foundation
#if POLARIS_IOS27 && canImport(PassKit)
import PassKit
#endif

/// Splitting a real charge with friends via Apple Cash (Wallet, iOS 27).
///
/// Distinct from `SplitTransactionView`, which only divides a transaction
/// across categories inside the app. This requests money from people through
/// Apple Cash so the user is actually paid back.
///
/// The Wallet "Split Bill with Apple Cash" API is beta, so the request flow is
/// gated behind `POLARIS_IOS27` and marked `VERIFY`. With the flag off (CI,
/// Xcode 26) the service reports itself unavailable and the UI hides the
/// entry point — nothing references the beta symbols.
struct SplitBillService: Sendable {
    /// Whether an Apple Cash split can be presented on this device right now.
    var isAvailable: Bool {
        #if POLARIS_IOS27 && canImport(PassKit)
        if #available(iOS 27.0, *) {
            // VERIFY against the iOS 27 SDK: Apple Cash availability check.
            return PKPaymentAuthorizationController.canMakePayments()
        }
        #endif
        return false
    }

    /// Requests `amount` split `ways` from the user's contacts via Apple Cash.
    /// Returns whether the split sheet was presented. No-op (false) wherever
    /// Apple Cash split is unavailable. Presents UI, so call on the main actor.
    @MainActor
    func requestSplit(amount: Decimal, ways: Int, note: String) async -> Bool {
        #if POLARIS_IOS27 && canImport(PassKit)
        if #available(iOS 27.0, *) {
            // VERIFY against the iOS 27 SDK: the Wallet Split-Bill request flow
            // (per-person share = amount / ways, requested over Apple Cash).
            let share = amount / Decimal(max(1, ways - 1))
            let request = PKApplePayLaterSplitRequest(
                amount: NSDecimalNumber(decimal: share),
                note: note
            )
            return await request.present()
        }
        #endif
        _ = (amount, ways, note)
        return false
    }
}
