import Foundation
import Observation
import WatchConnectivity

/// Receives the widget snapshot from the iPhone over WatchConnectivity and
/// caches it in UserDefaults so the app has data immediately on next launch.
@Observable
@MainActor
final class WatchSnapshotStore {
    static let shared = WatchSnapshotStore()

    private(set) var snapshot: WidgetSnapshot?
    private let cacheKey = "watch.snapshot"
    private let receiver = SessionReceiver()

    init() {
        if let data = UserDefaults.standard.data(forKey: cacheKey),
           let cached = try? JSONDecoder().decode(WidgetSnapshot.self, from: data) {
            snapshot = cached
        }
        receiver.onSnapshotData = { [weak self] data in
            Task { @MainActor in
                guard let self,
                      let decoded = try? JSONDecoder().decode(WidgetSnapshot.self, from: data) else { return }
                self.snapshot = decoded
                UserDefaults.standard.set(data, forKey: self.cacheKey)
            }
        }
    }

    func activate() {
        receiver.activate()
    }

    /// Nonisolated WCSession plumbing; hops to the main actor with the data.
    private final class SessionReceiver: NSObject, WCSessionDelegate, @unchecked Sendable {
        var onSnapshotData: ((Data) -> Void)?

        func activate() {
            guard WCSession.isSupported() else { return }
            WCSession.default.delegate = self
            WCSession.default.activate()
        }

        func session(
            _ session: WCSession,
            activationDidCompleteWith activationState: WCSessionActivationState,
            error: Error?
        ) {
            let context = session.receivedApplicationContext
            if let data = context["snapshot"] as? Data {
                onSnapshotData?(data)
            }
        }

        func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
            if let data = applicationContext["snapshot"] as? Data {
                onSnapshotData?(data)
            }
        }
    }
}
