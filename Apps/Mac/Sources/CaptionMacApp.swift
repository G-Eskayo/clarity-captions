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
            CallPopupWindow(model: model, calls: model.calls)
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
/// call included) while pinned, and captioning from the moment it opens, as "Captions start when your call does" says.
struct CallPopupWindow: View {
    @ObservedObject var model: CaptionMacModel
    @ObservedObject var calls: CallFlow
    @State private var window: NSWindow?

    var body: some View {
        let control = PrimaryControl.for(model.state)
        VStack(spacing: 0) {
            ZStack {
                CallPopupView(
                    lines: model.popupLines,
                    status: CallPopupView.Status(model.state, hasLines: !model.popupLines.isEmpty),
                    style: model.style,
                    buttonTitle: control.title,
                    buttonEnabled: control.isEnabled && calls.arrival.step != .ended,   // #178: answer the save question first
                    onPrimary: { control.action == .stop ? model.stop() : model.start() },
                    onPickLook: { preset in
                        model.style.background = preset.background
                        model.style.text = preset.text
                    },
                    pinned: $model.pinned,
                    statusWords: calls.statusWords(for: model.state),
                    emptyWords: calls.emptyWords(for: model.state)
                )
                .frame(minWidth: 360, minHeight: 300)
                .id(calls.conversationToken)   // #178: room and call conversations fade across
                .transition(.opacity)
            }
            CallBannerSlot(calls: calls, style: model.style)   // #178: a call arriving mid-conversation
        }
        .background(model.style.background.color)
        .background(WindowFinder(window: $window))
        .onChange(of: window) { _, _ in applyPin() }
        .onChange(of: model.pinned) { _, _ in applyPin() }
        .onChange(of: model.state) { _, state in NSLog("[calls] state %@", "\(state)") }
        .onAppear { if !CallAudioSelfTest.isRequested { calls.start(); model.start() } }
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
