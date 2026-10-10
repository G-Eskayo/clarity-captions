import SwiftUI

@main
struct SpikeApp: App {
    init() {
        _ = LaunchClock.start
        DemoMode.applyLookOverrides()
    }

    var body: some Scene {
        WindowGroup { RootView() }
    }
}
