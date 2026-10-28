import SwiftUI
import CaptionCore

@main
struct CaptionMacApp: App {
    /// The app's name everywhere a person sees it: Dock, menu bar, window (#172; "CaptionMac" was the working name from #41).
    static let windowTitle = "Seal Speak"

    @StateObject private var model = CaptionMacModel()

    init() {
        BundledFonts.register()
        MarvinScreenshot.runIfRequested()
        CallAudioSelfTest.runIfRequested()
        MarvinScreenshot.scheduleLiveSnapshotIfRequested()
        HideCheck.runIfRequested()
    }

    var body: some Scene {
        WindowGroup(CaptionMacApp.windowTitle, id: "main") {
            CallPopupWindow(model: model)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 440, height: 420)
        .windowResizability(.contentMinSize)

        MenuBarExtra("Seal Speak", systemImage: MenuBarPresentation.symbolName(for: model.state)) {
            MenuBarControlView(model: model)
        }
    }
}

/// The live pop-up (#172): the model's captions in `CallPopupView`, kept above other windows (a full-screen FaceTime
/// call included) while pinned. It opens with captions off, like the iPhone app: the owner presses Start captions
/// (#188). Starting on open turned the mic on unasked, and that first session came up dead until Stop, Start.
struct CallPopupWindow: View {
    @ObservedObject var model: CaptionMacModel
    @State private var window: NSWindow?

    var body: some View {
        let control = PrimaryControl.for(model.state)
        CallPopupView(
            lines: model.popupLines,
            status: CallPopupView.Status(model.state, hasLines: !model.popupLines.isEmpty),
            style: model.style,
            buttonTitle: control.title,
            buttonEnabled: control.isEnabled,
            onPrimary: { control.action == .stop ? model.stop() : model.start() },
            onPickLook: { preset in
                model.style.background = preset.background
                model.style.text = preset.text
            },
            pinned: $model.pinned
        )
        .frame(minWidth: 360, minHeight: 300)
        .background(WindowFinder(window: $window))
        .onChange(of: window) { _, _ in applyPin() }
        .onChange(of: model.pinned) { _, _ in applyPin() }
    }

    private func applyPin() {
        guard let window else { return }
        window.level = model.pinned ? .floating : .normal
        window.collectionBehavior = model.pinned ? [.canJoinAllSpaces, .fullScreenAuxiliary] : []
        window.isMovableByWindowBackground = true
    }
}

/// Hands back the NSWindow a SwiftUI view lives in.
private struct WindowFinder: NSViewRepresentable {
    @Binding var window: NSWindow?
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { window = view.window }
        return view
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
}
