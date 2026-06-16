import SwiftData
import SwiftUI

/// Savings goals funded out of the daily allowance. Each active goal's
/// per-day reservation shows up as a line in the safe-to-spend explanation.
struct GoalsView: View {
    @Environment(AppEnvironment.self) private var appEnvironment
    @Environment(\.modelContext) private var modelContext
    // Honor the user's drag order first, falling back to creation order for
    // goals saved before reordering existed (all sortIndex 0).
    @Query(sort: [SortDescriptor(\SavingsGoal.sortIndex), SortDescriptor(\SavingsGoal.createdAt)])
    private var goals: [SavingsGoal]

    @State private var editingGoal: SavingsGoal?
    @State private var showNewGoal = false

    var body: some View {
        Group {
            if goals.isEmpty {
                ScrollView {
                    EmptyStateView(
                        systemImage: "flag.checkered",
                        title: "No goals yet",
                        message: "Goals reserve a slice of your daily allowance, so saving happens on pace instead of from leftovers.",
                        actionTitle: "Create a goal",
                        action: { showNewGoal = true }
                    )
                    .padding(.top, 60)
                    .padding()
                }
            } else {
                List {
                    ForEach(goals) { goal in
                        goalCard(goal)
                            .glassListRow()
                    }
                    .onMove(perform: reorder)

                    Card {
                        Label {
                            Text("Active goals reserve \(totalReservation.currency())/day from safe-to-spend — tap “Why this number?” on Home to see it. Drag to reorder.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        } icon: {
                            Image(systemName: "sparkles").foregroundStyle(Theme.accent)
                        }
                    }
                    .glassListRow()
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .background(AppBackground())
        .navigationTitle("Goals")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showNewGoal = true } label: { Image(systemName: "plus") }
                    .accessibilityLabel("New goal")
            }
        }
        .sheet(isPresented: $showNewGoal) {
            GoalEditorView(goal: nil)
        }
        .sheet(item: $editingGoal) { goal in
            GoalEditorView(goal: goal)
        }
    }

    private var totalReservation: Decimal {
        goals.filter { !$0.isCompleted }.reduce(0) { $0 + $1.dailyReservation() }
    }

    /// Persist a drag-to-reorder by rewriting every goal's `sortIndex` to its
    /// new position, so the order sticks and syncs across devices.
    private func reorder(from offsets: IndexSet, to destination: Int) {
        var ordered = goals
        ordered.move(fromOffsets: offsets, toOffset: destination)
        for (index, goal) in ordered.enumerated() {
            goal.sortIndex = index
        }
        save()
    }

    private func goalCard(_ goal: SavingsGoal) -> some View {
        Card {
            HStack(spacing: 14) {
                ZStack {
                    ProgressRing(progress: goal.progress, lineWidth: 7, size: 58)
                    Text(goal.emoji).font(.title3)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(goal.name).font(.headline)
                    HStack(spacing: 4) {
                        AmountText(amount: goal.fundedAmount, font: .subheadline, showCents: false)
                        Text("of \(goal.targetAmount.currency(showCents: false))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if goal.isCompleted {
                        Label("Funded", systemImage: "checkmark.seal.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.positive)
                    } else {
                        Text("\(goal.dailyReservation().currency())/day" + (goal.targetDate.map { " · by \($0.shortDay)" } ?? ""))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Menu {
                    ForEach([25, 50, 100], id: \.self) { amount in
                        Button("Add \(Decimal(amount).currency(showCents: false))") {
                            fund(goal, amount: Decimal(amount))
                        }
                    }
                    Button("Edit…") { editingGoal = goal }
                    Button("Delete", role: .destructive) {
                        modelContext.delete(goal)
                        save()
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .sensoryFeedback(.impact(weight: .light), trigger: goal.fundedAmount)
    }

    private func fund(_ goal: SavingsGoal, amount: Decimal) {
        goal.fundedAmount = min(goal.targetAmount, goal.fundedAmount + amount)
        save()
    }

    private func save() {
        try? modelContext.save()
        Task { await appEnvironment.pipeline.recompute(in: modelContext) }
    }
}

struct GoalEditorView: View {
    var goal: SavingsGoal?

    @Environment(AppEnvironment.self) private var appEnvironment
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var emoji = "🎯"
    @State private var target: Double = 1000
    @State private var hasDeadline = false
    @State private var deadline = Calendar.current.date(byAdding: .month, value: 3, to: .now) ?? .now

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Goal name", text: $name)
                    TextField("Emoji", text: $emoji)
                }
                Section("Target") {
                    HStack {
                        Slider(value: $target, in: 100...25_000, step: 100)
                        Text(Decimal(target).currency(showCents: false))
                            .font(.headline)
                            .monospacedDigit()
                            .frame(width: 90, alignment: .trailing)
                    }
                    Toggle("Target date", isOn: $hasDeadline)
                    if hasDeadline {
                        DatePicker("By", selection: $deadline, in: Date.now..., displayedComponents: .date)
                    }
                }
            }
            .navigationTitle(goal == nil ? "New Goal" : "Edit Goal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear {
                guard let goal else { return }
                name = goal.name
                emoji = goal.emoji
                target = goal.targetAmount.doubleValue
                hasDeadline = goal.targetDate != nil
                if let date = goal.targetDate { deadline = date }
            }
        }
    }

    private func save() {
        let saved = goal ?? SavingsGoal(name: name, targetAmount: Decimal(target))
        if goal == nil {
            // New goals sort to the end of the user's order.
            let lastIndex = (try? modelContext.fetch(FetchDescriptor<SavingsGoal>()))?
                .map(\.sortIndex).max() ?? -1
            saved.sortIndex = lastIndex + 1
            modelContext.insert(saved)
        }
        saved.name = name
        saved.emoji = emoji.isEmpty ? "🎯" : String(emoji.prefix(2))
        saved.targetAmount = Decimal(target)
        saved.targetDate = hasDeadline ? deadline : nil
        try? modelContext.save()
        Task { await appEnvironment.pipeline.recompute(in: modelContext) }
        dismiss()
    }
}

#Preview {
    NavigationStack { GoalsView() }
        .environment(AppEnvironment.mock())
        .modelContainer(ModelContainerFactory.preview())
}
