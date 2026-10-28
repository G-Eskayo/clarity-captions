import SwiftUI
import CaptionCore

@main
struct CaptionMacApp: App {
    @StateObject private var model = CaptionMacModel()

    init() {
        BundledFonts.register()
        MarvinScreenshot.runIfRequested()
        CallAudioSelfTest.runIfRequested()
    }

    var body: some Scene {
        WindowGroup("Captions", id: "main") {
            CaptionWindowView(model: model)
                .frame(minWidth: 400, minHeight: 300)
        }
        .windowResizability(.contentMinSize)

        MenuBarExtra("Seal", systemImage: MenuBarPresentation.symbolName(for: model.state)) {
            MenuBarControlView(model: model)
        }
    }
}
