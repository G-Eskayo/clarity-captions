import CaptionCore
import CaptionUI
import SwiftUI

/// The call-captions pop-up (#172, design A approved in PR #174): a small always-on-top window that captions the call
/// by itself, with one Start/Stop button. The same view draws the live window and the screenshot mock-up, so what Gil
/// approved is what ships.
struct CallPopupView: View {
    struct Line: Identifiable {
        let id: Int
        /// Session speaker slot, nil until the diarizer has said who spoke.
        let speaker: Int?
        let name: String?
        let text: String
        var volatile = false
        /// #246 mock-up: the line's translation, the language of what was said, and how many of the translation's
        /// words the voice has said (#233). The Mac doesn't translate yet; only the screenshot mock-up sets these.
        var translation: String? = nil
        var saidLanguage: String? = nil
        var speakingFirm: Int? = nil
    }

    enum Status: Equatable {
        /// Captioning, nothing said yet.
        case waiting
        case captioning
        case starting
        /// Not captioning: stopped, paused or failed, with the words to show.
        case stopped(String)
    }

    let lines: [Line]
    let status: Status
    let style: CaptionStyle
    /// Start captions / Getting ready… as a pill; while captioning, the iPhone's small X (#178).
    let control: PrimaryControl
    var buttonEnabled = true
    var onPrimary: () -> Void = {}
    /// The gear: Settings, as on the iPhone (#172 parity).
    var onGear: () -> Void = {}
    /// The list icon opposite the gear: saved conversations, as on the iPhone (#137 option A).
    var onSaved: () -> Void = {}
    /// A long click on the captions: brings back the dim with [ Save ] / [ New ], as a hold does on the iPhone.
    var onHoldEmptySpace: () -> Void = {}
    /// Right-click / Control-click on the captions: the same two choices as a menu.
    var canSave = false
    var onSave: () -> Void = {}
    var onNew: () -> Void = {}
    /// Drawn over the captions (the iPhone's dim with [ Save ] / [ New ]).
    var captionsOverlay: AnyView? = nil
    /// The room's loudness for the Listening light (#180): red, brighter while people talk.
    var roomLevelDBFS: Double? = nil
    /// Replaces the top bar's words: "Captioning your FaceTime call" only while a call app is really in a call (#178).
    var statusOverride: String? = nil
    /// #246 mock-up: how translated lines are drawn.
    var translatedLook: TranslatedCaptionLook = .today

    /// The Start captions pill's height on the Mac (its size before the iPhone's control came in).
    static let pillHeight: CGFloat = 47
    /// The 14 pt between the newest words and the control.
    static let controlGap: CGFloat = 14

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var compact: Bool { control.presentation == .compact }
    /// Room kept at the bottom of the captions for the control: the X's corner while captioning, the pill's row otherwise.
    private var controlReserve: CGFloat {
        (compact ? PrimaryControl.compactDiameter + 16 : Self.pillHeight + GummyButtonStyle.restingLip + 24) + Self.controlGap
    }

    private var speakerColors: [RGBA] {
        let colors = style.preset?.speakers ?? SpeakerPalette.colors(on: style.background, text: style.text)
        return colors.isEmpty ? [style.text] : colors
    }
    private var captionFont: Font { style.font(for: .large, scaled: 0.82) }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            ZStack {
                if lines.isEmpty { waiting } else { captions }
                captionsOverlay
            }
            .contentShape(Rectangle())
            .onLongPressGesture(minimumDuration: 0.5, perform: onHoldEmptySpace)
            .contextMenu {
                Button(String(localized: "Save conversation"), action: onSave).disabled(!canSave)
                Button(String(localized: "New conversation"), action: onNew)
            }
            // The captions run down to the control, keeping a gap so the newest words never run into it.
            .padding(.bottom, controlReserve)
        }
        // The iPhone's control and layout (#178, owner 2026-10-28): the Start pill centered at the bottom; while
        // captioning it sweeps into the small red X in the bottom-right corner, so captions get the screen. Reduce
        // Motion: a crossfade.
        .overlay(alignment: .bottom) {
            GeometryReader { geo in
                MorphingControl(control: control, fullWidth: geo.size.width, fill: style.text, label: style.background,
                                pillHeight: Self.pillHeight, titleFont: .system(size: 19, weight: .semibold), action: onPrimary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: compact ? .bottomTrailing : .bottom)
            }
            .frame(height: max(Self.pillHeight, PrimaryControl.compactDiameter) + GummyButtonStyle.restingLip)
            .disabled(!buttonEnabled)
            .opacity(buttonEnabled ? 1 : 0.5)
            .keyboardShortcut(.space, modifiers: [])
            .padding(.horizontal, compact ? 16 : 18)
            .padding(.bottom, compact ? 16 : 24)   // a little more room under Start (owner, 2026-10-28)
            .animation(Fluid.quick(reduceMotion), value: compact)
        }
        .background(style.background.color)
        .environment(\.colorScheme, style.background.isDark ? .dark : .light)
    }

    /// Never names a call app unless one is really in a call (owner, 2026-10-28): the Mac hears every sound plus the mic,
    /// so "FaceTime" or "the room" would often be wrong.
    private var topWords: String {
        if let statusOverride { return statusOverride }
        return switch status {
        case .waiting: String(localized: "Listening")
        case .captioning: String(localized: "Captioning")
        case .starting: String(localized: "Getting ready…")
        case .stopped: String(localized: "Captions are off")
        }
    }

    private var topBar: some View {
        HStack {
            Button(action: onGear) {
                Image(systemName: "gearshape").font(.system(size: 17, weight: .regular)).foregroundStyle(style.gear.color)
            }
            .buttonStyle(PressableIconStyle(tint: style.gear.color))
            .help(String(localized: "Settings"))
            .accessibilityLabel(String(localized: "Settings"))
            Spacer()
            HStack(spacing: 6) {
                if status == .captioning || status == .waiting {
                    ListeningLightView(background: style.background, roomLevelDBFS: roomLevelDBFS, size: 7)
                } else {
                    Circle().fill(style.text.color.opacity(0.35)).frame(width: 7, height: 7)
                }
                Text(topWords)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(style.text.color.opacity(0.75))
            }
            Spacer()
            Button(action: onSaved) {
                Image(systemName: "list.bullet").font(.system(size: 17, weight: .regular)).foregroundStyle(style.gear.color)
            }
            .buttonStyle(PressableIconStyle(tint: style.gear.color))
            .help(String(localized: "Saved conversations"))
            .accessibilityLabel(String(localized: "Saved conversations"))
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 8)
    }

    private var captions: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(lines) { line in
                        VStack(alignment: .leading, spacing: 2) {
                            if let speaker = line.speaker {
                                Text(line.name ?? String(localized: "Speaker \(speaker + 1)"))
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(speakerColors[speaker % speakerColors.count].color)
                            }
                            if let translation = line.translation {
                                TranslatedCaptionView(look: translatedLook, translated: translation, said: line.text,
                                                      saidLanguage: line.saidLanguage, speakingFirm: line.speakingFirm,
                                                      font: captionFont, saidFont: .system(size: 14),
                                                      text: style.text.color, muted: style.text.color.opacity(0.62), mark: style.gear.color,
                                                      volatileOpacity: style.volatileOpacity, startsOpen: line.id == lines.dropLast().last?.id)
                            } else {
                                Text(line.text)
                                    .font(captionFont)
                                    .foregroundStyle(style.text.color.opacity(line.volatile ? style.volatileOpacity : 1))
                                    .fixedSize(horizontal: false, vertical: true)
                                    .textSelection(.enabled)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .id(line.id)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 10)
            }
            .onChange(of: lines.last?.text) { _, _ in
                if let last = lines.last { proxy.scrollTo(last.id, anchor: .bottom) }
            }
        }
    }

    private var waiting: some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: "phone.bubble")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(style.gear.color)
            Text(waitingWords)
                .font(.system(size: 17))
                .foregroundStyle(style.text.color.opacity(0.85))
                .multilineTextAlignment(.center)
            Spacer()
        }
        .frame(maxWidth: .infinity, minHeight: 220)
        .padding(.horizontal, 24)
    }

    private var waitingWords: String {
        switch status {
        case .stopped(let words): words
        case .starting: String(localized: "Getting ready…")
        case .waiting, .captioning: String(localized: "Captions appear when someone speaks.")
        }
    }
}

extension CallPopupView.Status {
    init(_ state: CaptionState, hasLines: Bool) {
        switch state {
        case .listening: self = hasLines ? .captioning : .waiting
        case .preparing: self = .starting
        case .idle: self = .stopped(String(localized: "Captions are off. Press Start captions when your call begins."))
        case .failed(let words): self = .stopped(words)
        case .pausedQuiet: self = .stopped(StatusWords.detail(for: state) ?? String(localized: "Captions paused after a quiet stretch."))
        }
    }
}
