import Foundation
#if canImport(WatchConnectivity)
import WatchConnectivity

/// Pushes the precomputed widget snapshot to the paired Apple Watch after
/// each recompute. App Group containers don't span devices —
/// WatchConnectivity does, and `applicationContext` keeps only the freshest
/// payload, which is exactly the semantics a snapshot wants.
final class WatchSync: NSObject, WCSessionDelegate, @unchecked Sendable {
    static let shared = WatchSync()

    func activate() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    func push() {
        guard WCSession.isSupported(),
              WCSession.default.activationState == .activated,
              let snapshot = SharedSnapshotStore.load(),
              let data = try? JSONEncoder().encode(snapshot) else { return }
        try? WCSession.default.updateApplicationContext(["snapshot": data])
    }

    // MARK: - WCSessionDelegate

    func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        if activationState == .activated { push() }
    }

    func sessionDidBecomeInactive(_ session: WCSession) {}

    func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }
}
#endif
