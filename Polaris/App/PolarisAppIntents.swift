import AppIntents
import Foundation

/// Siri / Shortcuts / Spotlight surface. Answers come from the widget
/// snapshot the pipeline writes after every recompute, so the intent is
/// instant and fully offline — no model call, no network.
struct SafeToSpendIntent: AppIntent {
    static let title: LocalizedStringResource = "Safe to Spend Today"
    static let description = IntentDescription(
        "Asks Polaris how much you can safely spend today."
    )

    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let snapshot = SharedSnapshotStore.load() else {
            return .result(dialog: "Polaris hasn't computed a number yet — open the app to sync your accounts.")
        }
        let today = snapshot.safeToSpendToday.currency(snapshot.currencyCode, showCents: false)
        let week = snapshot.safeToSpendWeek.currency(snapshot.currencyCode, showCents: false)
        return .result(dialog: "You can safely spend \(today) today, and \(week) over the rest of the week.")
    }
}

struct UpcomingBillsIntent: AppIntent {
    static let title: LocalizedStringResource = "Upcoming Bills"
    static let description = IntentDescription(
        "Asks Polaris which recurring charges are coming up."
    )

    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let snapshot = SharedSnapshotStore.load(), !snapshot.upcomingBills.isEmpty else {
            return .result(dialog: "No upcoming bills detected right now.")
        }
        let bills = snapshot.upcomingBills.prefix(3)
            .map { "\($0.merchant) \($0.amount.currency(snapshot.currencyCode, showCents: false)) on \($0.dueDate.shortDay)" }
            .joined(separator: ", ")
        return .result(dialog: "Coming up: \(bills).")
    }
}

/// Timeframe the conversational check-in can ask about.
enum SpendCheckTimeframe: String, AppEnum {
    case today
    case week

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Timeframe")
    static let caseDisplayRepresentations: [SpendCheckTimeframe: DisplayRepresentation] = [
        .today: "today",
        .week: "this week",
    ]
}

/// Conversational spending check-in (App Intents 2.0 direction). When the user
/// doesn't say a timeframe, Siri asks the follow-up via `requestValueDialog`,
/// then answers from the widget snapshot — instant, offline, no model call.
///
/// The follow-up parameter resolution is a stable API, so this ships today. On
/// iOS 27 the answer is enriched with a pace-aware nudge and an offer to
/// continue the conversation; that branch is gated behind `POLARIS_IOS27`.
struct SpendingCheckInIntent: AppIntent {
    static let title: LocalizedStringResource = "Spending Check-In"
    static let description = IntentDescription(
        "A conversational check on how your spending is tracking."
    )

    @Parameter(title: "Timeframe", requestValueDialog: "For today, or the rest of the week?")
    var timeframe: SpendCheckTimeframe

    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let snapshot = SharedSnapshotStore.load() else {
            return .result(dialog: "Polaris hasn't computed a number yet — open the app to sync your accounts.")
        }
        let amount = timeframe == .today ? snapshot.safeToSpendToday : snapshot.safeToSpendWeek
        let label = timeframe == .today ? "today" : "over the rest of the week"
        let money = amount.currency(snapshot.currencyCode, showCents: false)

        var dialog = "You can safely spend \(money) \(label)."
        // Pace-aware nudge — iOS 27 leans into multi-turn, conversational
        // answers, so we add context the user would naturally ask for next.
        if #available(iOS 27.0, *) {
            if snapshot.spendPaceDelta > 0.1 {
                dialog += " Heads up — you're running \(Int(snapshot.spendPaceDelta * 100))% over pace this month."
            } else if snapshot.spendPaceDelta < -0.1 {
                dialog += " You're \(Int(-snapshot.spendPaceDelta * 100))% under pace, so there's a little cushion."
            }
            if let bill = snapshot.upcomingBills.first {
                let billAmount = bill.amount.currency(snapshot.currencyCode, showCents: false)
                dialog += " \(bill.merchant) for \(billAmount) is due \(bill.dueDate.shortDay)."
            }
        }
        return .result(dialog: IntentDialog(stringLiteral: dialog))
    }
}

struct PolarisShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: SafeToSpendIntent(),
            phrases: [
                "How much can I spend in \(.applicationName)",
                "Ask \(.applicationName) what's safe to spend today",
            ],
            shortTitle: "Safe to Spend",
            systemImageName: "sparkles"
        )
        AppShortcut(
            intent: UpcomingBillsIntent(),
            phrases: [
                "What bills are coming up in \(.applicationName)",
            ],
            shortTitle: "Upcoming Bills",
            systemImageName: "calendar.badge.clock"
        )
        AppShortcut(
            intent: SpendingCheckInIntent(),
            phrases: [
                "How am I doing in \(.applicationName)",
                "Check in on my spending in \(.applicationName)",
            ],
            shortTitle: "Spending Check-In",
            systemImageName: "checkmark.circle"
        )
    }
}
