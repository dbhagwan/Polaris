import SwiftData
import SwiftUI

/// User-authored categorization rules: "anything containing X is always Y".
/// Rules outrank heuristics and the model (only direct corrections beat
/// them) and apply retroactively when saved.
struct RulesView: View {
    @Environment(AppEnvironment.self) private var appEnvironment
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \UserRule.createdAt) private var rules: [UserRule]
    @Query private var transactions: [Transaction]

    @State private var showNewRule = false

    var body: some View {
        List {
            if rules.isEmpty {
                Text("Rules pin a merchant pattern to a category, forever. Example: “AIRBNB” → Travel.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .glassListRow()
            }
            ForEach(rules) { rule in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("“\(rule.pattern)”")
                            .font(.subheadline.weight(.medium))
                        HStack(spacing: 4) {
                            Image(systemName: rule.category.systemImage)
                            Text(rule.category.displayName)
                            if rule.markEssential { Text("· essential") }
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Toggle("", isOn: Binding(
                        get: { rule.isEnabled },
                        set: { enabled in
                            rule.isEnabled = enabled
                            persistAndRecompute()
                        }
                    ))
                    .labelsHidden()
                }
                .glassListRow()
            }
            .onDelete { offsets in
                for index in offsets { modelContext.delete(rules[index]) }
                persistAndRecompute()
            }
        }
        .scrollContentBackground(.hidden)
        .background(AppBackground())
        .navigationTitle("Rules")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showNewRule = true } label: { Image(systemName: "plus") }
                    .accessibilityLabel("New rule")
            }
        }
        .sheet(isPresented: $showNewRule) {
            RuleEditorView { rule in
                modelContext.insert(rule)
                applyRetroactively(rule)
                persistAndRecompute()
            }
        }
    }

    /// New rules fix history, not just the future.
    private func applyRetroactively(_ rule: UserRule) {
        for transaction in transactions
        where transaction.categorySource != .user && rule.matches(transaction.normalizedDescription) {
            transaction.category = rule.category
            transaction.categorySource = .rules
            transaction.categoryConfidence = 0.95
            transaction.isEssential = rule.markEssential
                || rule.category.isTypicallyFixed
                || rule.category == .groceries
            transaction.needsAIReview = false
        }
    }

    private func persistAndRecompute() {
        try? modelContext.save()
        Task { await appEnvironment.pipeline.recompute(in: modelContext) }
    }
}

struct RuleEditorView: View {
    var onSave: (UserRule) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var pattern = ""
    @State private var category: SpendingCategory = .shopping
    @State private var markEssential = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Descriptor contains…", text: $pattern)
                        .autocorrectionDisabled()
                } footer: {
                    Text("Case-insensitive match against the cleaned-up merchant name.")
                }
                Picker("Category", selection: $category) {
                    ForEach(SpendingCategory.allCases) { category in
                        Label(category.displayName, systemImage: category.systemImage)
                            .tag(category)
                    }
                }
                Toggle("Count as essential", isOn: $markEssential)
            }
            .navigationTitle("New Rule")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(UserRule(
                            pattern: pattern.trimmingCharacters(in: .whitespaces),
                            category: category,
                            markEssential: markEssential
                        ))
                        dismiss()
                    }
                    .disabled(pattern.trimmingCharacters(in: .whitespaces).count < 2)
                }
            }
        }
    }
}

#Preview {
    NavigationStack { RulesView() }
        .environment(AppEnvironment.mock())
        .modelContainer(ModelContainerFactory.preview())
}
