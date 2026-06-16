import Foundation
#if POLARIS_IOS27
import FoundationModels
#endif

/// On-device personalization of the transaction classifier.
///
/// iOS 27 adds on-device LoRA fine-tuning of the system language model. Instead
/// of re-deriving the user's preferences from few-shot examples on every call,
/// we train a small adapter on their own category corrections so the model
/// internalizes how *this* person files merchants. The adapter is written to
/// the app sandbox, never leaves the device, and is attached to each
/// `LanguageModelSession` for inference.
///
/// Everything that touches the beta LoRA training/adapter API is gated behind
/// the `POLARIS_IOS27` compile flag (off in CI and Xcode 26). With the flag
/// off this type still compiles and does useful work: it accumulates the
/// training set and the retrain signal so the corpus is ready the moment the
/// flag is flipped on a device running the iOS 27 SDK. Inference simply falls
/// back to few-shot prompting, exactly as today.
///
/// The exact training entry points are beta and marked `VERIFY` — confirm the
/// symbols against the installed SDK before shipping.
actor PersonalizationAdapter {
    /// One labelled correction: the normalized merchant the user re-filed and
    /// the category they chose. This is the LoRA training set.
    struct TrainingExample: Codable, Sendable, Equatable {
        var merchant: String
        var categoryID: String
        var recordedAt: Date
    }

    private var examples: [TrainingExample]
    /// Example count captured at the last successful train, so we only retrain
    /// once enough *new* corrections have accumulated.
    private var trainedAtCount: Int
    private var isTraining = false

    /// Retrain once this many new corrections land since the last train. The
    /// adapter is cheap on device but not free, so we batch.
    private let retrainThreshold = 12
    /// Keep the corpus bounded; the most recent corrections describe current
    /// habits best.
    private let maxExamples = 500

    private let storeURL: URL

    init(storeURL: URL = PersonalizationAdapter.defaultStoreURL) {
        self.storeURL = storeURL
        if let data = try? Data(contentsOf: storeURL),
           let saved = try? JSONDecoder().decode(Persisted.self, from: data) {
            examples = saved.examples
            trainedAtCount = saved.trainedAtCount
        } else {
            examples = []
            trainedAtCount = 0
        }
    }

    // MARK: - Training-set collection (runs on every build)

    /// Record a user correction into the training set. De-dupes on merchant so
    /// the latest label for a merchant wins instead of stacking.
    func record(merchant: String, category: SpendingCategory) {
        let key = merchant.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !key.isEmpty else { return }
        examples.removeAll { $0.merchant == key }
        examples.append(TrainingExample(merchant: key, categoryID: category.rawValue, recordedAt: .now))
        if examples.count > maxExamples {
            examples.removeFirst(examples.count - maxExamples)
            trainedAtCount = min(trainedAtCount, examples.count)
        }
        persist()
    }

    var trainingExampleCount: Int { examples.count }

    var pendingCorrections: Int { max(0, examples.count - trainedAtCount) }

    var shouldRetrain: Bool {
        examples.count >= retrainThreshold && pendingCorrections >= retrainThreshold
    }

    /// Kick a retrain when enough new corrections have accrued. Safe to call
    /// after every recompute; it no-ops unless the threshold is crossed.
    func retrainIfNeeded() async {
        guard shouldRetrain, !isTraining else { return }
        await retrain()
    }

    // MARK: - Training + inference (iOS 27 beta, flag-gated)

    private func retrain() async {
        isTraining = true
        defer { isTraining = false }

        #if POLARIS_IOS27
        if #available(iOS 27.0, *) {
            do {
                try await trainAdapter(on: examples)
                trainedAtCount = examples.count
                persist()
            } catch {
                // Leave trainedAtCount untouched so we retry next cycle.
            }
            return
        }
        #endif
        // Flag off / pre-iOS-27: corpus is collected and ready; no training.
        trainedAtCount = examples.count
        persist()
    }

    #if POLARIS_IOS27
    /// File URL of the trained adapter, when one exists.
    private var adapterURL: URL {
        storeURL.deletingLastPathComponent().appendingPathComponent("classifier.adapter")
    }

    @available(iOS 27.0, *)
    private func trainAdapter(on examples: [TrainingExample]) async throws {
        // VERIFY against the iOS 27 SDK: the on-device adapter trainer API.
        // The shape below mirrors the announced flow — assemble labelled
        // prompt/response pairs, fit a LoRA adapter, write it to the sandbox.
        let data = examples.map { example in
            SystemLanguageModel.Adapter.TrainingExample(
                prompt: "Merchant: \(example.merchant.capitalized)",
                response: example.categoryID
            )
        }
        let trainer = SystemLanguageModel.Adapter.Trainer()
        let adapter = try await trainer.train(on: data)
        try adapter.write(to: adapterURL)
    }

    /// The personalized model when a trained adapter is available, else the
    /// base model. Read by `FoundationModelsAIService` to build sessions.
    @available(iOS 27.0, *)
    func adaptedModel() -> SystemLanguageModel? {
        guard FileManager.default.fileExists(atPath: adapterURL.path),
              let adapter = try? SystemLanguageModel.Adapter(fileURL: adapterURL) else {
            return nil
        }
        return SystemLanguageModel(adapter: adapter)
    }
    #endif

    // MARK: - Persistence

    private struct Persisted: Codable {
        var examples: [TrainingExample]
        var trainedAtCount: Int
    }

    private func persist() {
        let payload = Persisted(examples: examples, trainedAtCount: trainedAtCount)
        guard let data = try? JSONEncoder().encode(payload) else { return }
        try? FileManager.default.createDirectory(
            at: storeURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? data.write(to: storeURL, options: .atomic)
    }

    static var defaultStoreURL: URL {
        URL.applicationSupportDirectory
            .appendingPathComponent("Personalization", isDirectory: true)
            .appendingPathComponent("classifier-corrections.json")
    }
}
