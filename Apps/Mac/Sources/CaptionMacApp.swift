import SwiftUI
import CaptionCore

@main
struct CaptionMacApp: App {
    @StateObject private var model = CaptionMacModel()

    var body: some Scene {
        WindowGroup("Captions", id: "main") {
            CaptionWindowView(model: model)
                .frame(minWidth: 400, minHeight: 300)
        }
        .windowResizability(.contentMinSize(CGSize(width: 400, height: 300)))

        MenuBarExtra("Seal", systemImage: MenuBarPresentation.symbolName(for: model.state)) {
            MenuBarControlView(model: model)
        }
    }
}
