import SwiftUI

@main
struct SpikeApp: App {
    init() { DemoMode.applyLookOverrides() }

    var body: some Scene {
        WindowGroup { RootView() }
    }
}
