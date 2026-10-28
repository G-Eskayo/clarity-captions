import SwiftUI
import CaptionCore

@main
struct CaptionMacApp: App {
    @StateObject private var model = CaptionMacModel()

    init() {
        BundledFonts.register()
        MarvinScreenshot.runIfRequested()
        CallAudioSelfTest.runIfRequested()
        MarvinScreenshot.scheduleLiveSnapshotIfRequested()
    }

    var body: some Scene {
        WindowGroup("Captions", id: "main") {
            CallPopupWindow(model: model)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 440, height: 420)
        .windowResizability(.contentMinSize)

        MenuBarExtra("Seal", systemImage: MenuBarPresentation.symbolName(for: model.state)) {
            MenuBarControlView(model: model)
        }
    }
}

/// The live pop-up (#172): the model's captions in `CallPopupView`, kept above other windows (a full-screen FaceTime
/// call included) while pinned, and captioning from the moment it opens, as "Captions start when your call does" says.
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
        .onAppear { if !CallAudioSelfTest.isRequested { model.start() } }
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
