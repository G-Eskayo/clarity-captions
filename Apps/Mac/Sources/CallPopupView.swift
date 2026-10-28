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
    let buttonTitle: String
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
            Button(action: onPrimary) {
                Text(buttonTitle)
                    .font(.system(size: 19, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(GummyButtonStyle(style: style))
            .disabled(!buttonEnabled)
            .keyboardShortcut(.space, modifiers: [])
            .padding(.horizontal, 18)
            .padding(.bottom, 14)
        }
        .background(style.background.color)
        .environment(\.colorScheme, style.background.isDark ? .dark : .light)
    }

    private var statusWords: String {
        switch status {
        case .waiting: String(localized: "Waiting for a FaceTime call")
        case .captioning: String(localized: "Captioning your FaceTime call")
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
                Text(statusWords)
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
                            Text(line.text)
                                .font(captionFont)
                                .foregroundStyle(style.text.color.opacity(line.volatile ? style.volatileOpacity : 1))
                                .fixedSize(horizontal: false, vertical: true)
                                .textSelection(.enabled)
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
        case .waiting, .captioning: String(localized: "Captions start when your call does.")
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
