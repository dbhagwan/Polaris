import SwiftData
import SwiftUI

@main
struct SpendriftApp: App {
    // Mock mode keeps the app fully navigable without a backend.
    // Flip to false (or drive via build configuration) once Backend/ is running.
    @State private var appEnvironment = AppEnvironment(useMocks: true)
    private let container = ModelContainerFactory.make()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(appEnvironment)
                // Dark-first, like Stocks/Robinhood — the glass design system
                // is built for dark surfaces.
                .preferredColorScheme(.dark)
        }
        .modelContainer(container)
    }
}
