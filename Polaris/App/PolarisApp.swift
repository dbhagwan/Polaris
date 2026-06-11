import SwiftData
import SwiftUI

@main
struct PolarisApp: App {
    // Mock mode keeps the app fully navigable without a backend.
    // Flip to false (or drive via build configuration) once Backend/ is running.
    @State private var appEnvironment = AppEnvironment(useMocks: true)
    @AppStorage("appearance") private var appearance = "system"
    private let container = ModelContainerFactory.make()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(appEnvironment)
                .preferredColorScheme(
                    appearance == "light" ? .light : appearance == "dark" ? .dark : nil
                )
        }
        .modelContainer(container)
    }
}
