import SwiftUI

/// Polaris on the wrist: the safe-to-spend number and next bills, fed by the
/// same precomputed snapshot the widgets use, delivered over
/// WatchConnectivity (App Group containers don't span devices).
@main
struct PolarisWatchApp: App {
    @State private var store = WatchSnapshotStore.shared

    var body: some Scene {
        WindowGroup {
            WatchHomeView()
                .environment(store)
        }
    }
}

struct WatchHomeView: View {
    @Environment(WatchSnapshotStore.self) private var store

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                if let snapshot = store.snapshot {
                    Text("SAFE TO SPEND")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .kerning(0.5)
                    Text(snapshot.safeToSpendToday.formatted(
                        .currency(code: snapshot.currencyCode).precision(.fractionLength(0))
                    ))
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .foregroundStyle(.mint)
                    .privacySensitive()
                    Text("\(snapshot.safeToSpendWeek.formatted(.currency(code: snapshot.currencyCode).precision(.fractionLength(0)))) this week")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    if !snapshot.upcomingBills.isEmpty {
                        Divider()
                        Text("UPCOMING")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                        ForEach(snapshot.upcomingBills.prefix(3)) { bill in
                            HStack {
                                Text(bill.merchant)
                                    .font(.footnote)
                                    .lineLimit(1)
                                Spacer()
                                Text(bill.amount.formatted(
                                    .currency(code: snapshot.currencyCode).precision(.fractionLength(0))
                                ))
                                .font(.footnote.weight(.semibold))
                                .privacySensitive()
                            }
                        }
                    }
                } else {
                    Image(systemName: "sparkles")
                        .font(.title2)
                        .foregroundStyle(.mint)
                    Text("Open Polaris on your iPhone to sync.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)
        }
        .onAppear { store.activate() }
    }
}
