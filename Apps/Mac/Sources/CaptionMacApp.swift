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
        .commands {
            // ⌘, opens Settings in the pop-up, the same Settings page as the iPhone's (#172 parity).
            CommandGroup(replacing: .appSettings) {
                Button(String(localized: "Settings…")) { model.go { $0.openSettings() } }
                    .keyboardShortcut(",", modifiers: .command)
            }
        }

        MenuBarExtra("Seal Speak", systemImage: MenuBarPresentation.symbolName(for: model.state)) {
            MenuBarControlView(model: model)
        }
    }
}

/// The live pop-up (#172): the model's captions in `CallPopupView`, kept above other windows (a full-screen FaceTime
/// call included; there's no pin to switch that off, owner 2026-10-28, ⌘H hides it). It opens with captions off, like
/// the iPhone app: the owner presses Start captions (#188). Starting on open turned the mic on unasked, and that first
/// session came up dead until Stop, Start.
struct CallPopupWindow: View {
    @ObservedObject var model: CaptionMacModel
    @State private var window: NSWindow?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            if model.nav.current == .captions {
                captionsPage.transition(.opacity)
            } else {
                page(model.nav.current)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .background(model.style.background.color)
                    .environment(\.colorScheme, model.style.background.isDark ? .dark : .light)
                    .transition(.opacity)
            }
        }
        .frame(minWidth: 360, minHeight: 300)
        .background(model.style.background.color)
        .background(WindowFinder(window: $window))
        .onChange(of: window) { _, _ in keepOnTop() }
        // No start on open (#188): captions start on Start captions. Only a screenshot scene acts on appear.
        .onAppear { if MarvinScene.isOn { MarvinScene.run(model) } }
    }

    private var style: CaptionStyle { model.style }
    private var veilAnimation: Animation { Fluid.fade(reduceMotion) }

    private var captionsPage: some View {
        let control = PrimaryControl.for(model.state)
        let saveState = model.session.saveButton(lines: model.stream.lines, names: model.speakerNames)
        return CallPopupView(
            lines: model.popupLines,
            status: CallPopupView.Status(model.state, hasLines: !model.popupLines.isEmpty),
            style: style,
            buttonTitle: control.title,
            buttonEnabled: control.isEnabled,
            onPrimary: { control.action == .stop ? model.stop() : model.start() },
            onGear: { model.go { $0.gearTapped() } },
            onSaved: { model.go { $0.openSavedFromCaptions() } },
            onHoldEmptySpace: { withAnimation(veilAnimation) { model.veil.holdOnEmptySpace(state: model.state) } },
            canSave: saveState == .save,
            onSave: { withAnimation(Fluid.saveMorph(reduceMotion)) { model.save() } },
            onNew: { withAnimation(veilAnimation) { model.requestNew() } },
            captionsOverlay: AnyView(pauseVeil),
            roomLevelDBFS: model.roomLevelDBFS
        )
    }

    /// The iPhone's dim over a paused conversation (mock-up 02): [ Save ] over [ New ], or New's question in their place.
    /// One click on the dim clears it, to read, scroll and copy.
    private var pauseVeil: some View {
        DimLayer(visible: model.veilShowing, color: style.background.color, reduceMotion: reduceMotion, onTap: {
            withAnimation(veilAnimation) {
                model.newQuestion.keep()
                model.veil.tap(state: model.state)
            }
        }) {
            if model.newQuestion.isAsking {
                InPlaceQuestionView(style: style,
                                    title: String(localized: "Start a new conversation?"),
                                    message: String(localized: "This one isn't saved."),
                                    yes: String(localized: "Start new"), yesIsDestructive: false,
                                    no: String(localized: "Keep it"), stacked: true,
                                    onYes: { withAnimation(veilAnimation) { if model.newQuestion.confirm() != nil { model.startNew() } } },
                                    onNo: { withAnimation(veilAnimation) { model.newQuestion.keep() } })
                    .transition(.opacity)
            } else {
                VStack(spacing: 24) {
                    saveButton
                    RetroWords(word: String(localized: "New"), color: style.text.color, background: style.background.color,
                               label: String(localized: "Start a new conversation"),
                               action: { withAnimation(veilAnimation) { model.requestNew() } })
                }
                .transition(.opacity)
            }
        }
    }

    /// [ Save ] → [ ✔ ] → [ Saved ], as on the iPhone.
    @ViewBuilder
    private var saveButton: some View {
        let green = SavedGreen.color(on: style.background).color
        let button = model.session.saveButton(lines: model.stream.lines, names: model.speakerNames)
        if model.showingSaveCheck || button != .unavailable {
            let save = !model.showingSaveCheck && button == .save
            RetroWords(word: model.showingSaveCheck ? "✔" : save ? String(localized: "Save") : String(localized: "Saved"),
                       color: save ? style.text.color : green, background: style.background.color,
                       label: save ? String(localized: "Save conversation")
                                   : model.showingSaveCheck ? String(localized: "Saved") : String(localized: "Conversation saved"),
                       action: save ? { withAnimation(Fluid.saveMorph(reduceMotion)) { model.save() } } : nil)
        }
    }

    /// Settings and its pages: the iPhone's own views, shared (#172 parity).
    @ViewBuilder
    private func page(_ screen: AppScreen) -> some View {
        switch screen {
        case .captions:
            EmptyView()
        case .settings:
            SettingsPage(style: $model.style, idleStop: $model.idleStop, store: model.store,
                         onGear: { model.go { $0.gearTapped() } },
                         onOpen: { screen in model.go { $0.open(screen) } })
        case .saved:
            if let store = model.store {
                SavedConversationsPage(backTitle: model.nav.savedOpenedFromCaptions ? String(localized: "Captions") : String(localized: "Settings"),
                                       store: store, style: style, onBack: { model.go { $0.back() } },
                                       onOpen: { id in model.go { $0.open(.savedConversation(id)) } })
                    .padding(.horizontal, 16)
            }
        case .savedConversation(let id):
            if let store = model.store {
                SavedConversationPage(store: store, id: id, style: style, onBack: { model.go { $0.back() } })
                    .padding(.horizontal, 16)
            }
        case .credits:
            CreditsPage(style: style, onBack: { model.go { $0.back() } }, onLicenseText: { model.go { $0.open(.licenseText) } })
                .padding(.horizontal, 16)
        case .licenseText:
            LicenseTextPage(style: style, onBack: { model.go { $0.back() } })
                .padding(.horizontal, 16)
        case .feedbackPreview:
            EmptyView()   // beta feedback is iPhone-only
        }
    }

    private func keepOnTop() {
        guard let window else { return }
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
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
