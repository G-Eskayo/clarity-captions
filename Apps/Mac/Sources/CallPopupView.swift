import CaptionCore
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
    var onPickLook: (CaptionPreset) -> Void = { _ in }
    @Binding var pinned: Bool
    /// Replaces the top bar's words, e.g. "Captioning the room" while no call is being captioned (#178).
    var statusWords: String? = nil
    /// Replaces the empty window's words, e.g. while captioning the room rather than waiting for a call (#178).
    var emptyWords: String? = nil

    private var speakerColors: [RGBA] {
        let colors = style.preset?.speakers ?? SpeakerPalette.colors(on: style.background, text: style.text)
        return colors.isEmpty ? [style.text] : colors
    }
    private var captionFont: Font { style.font(for: .large, scaled: 0.82) }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            if lines.isEmpty { waiting } else { captions }
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

    private var topWords: String {
        if let statusWords { return statusWords }
        return switch status {
        case .waiting: String(localized: "Waiting for a FaceTime call")
        case .captioning: String(localized: "Captioning your FaceTime call")
        case .starting: String(localized: "Getting ready…")
        case .stopped: String(localized: "Captions are off")
        }
    }

    private var topBar: some View {
        HStack {
            Menu {
                ForEach(CaptionPreset.all, id: \.id) { preset in
                    Button(preset.name) { onPickLook(preset) }
                }
            } label: {
                Image(systemName: "gearshape").font(.system(size: 17, weight: .regular)).foregroundStyle(style.gear.color)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Look")
            Spacer()
            HStack(spacing: 6) {
                Circle().fill(status == .captioning ? style.saved.color : style.text.color.opacity(0.35)).frame(width: 7, height: 7)
                Text(topWords)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(style.text.color.opacity(0.75))
            }
            Spacer()
            Button { pinned.toggle() } label: {
                Image(systemName: pinned ? "pin.fill" : "pin").font(.system(size: 13)).foregroundStyle(style.gear.color.opacity(0.7))
            }
            .buttonStyle(.plain)
            .help(pinned ? "Stays on top of other windows" : "Doesn't stay on top")
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
        if let emptyWords { return emptyWords }
        return switch status {
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
