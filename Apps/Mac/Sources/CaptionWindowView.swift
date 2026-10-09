import SwiftUI
import CaptionCore

struct CaptionWindowView: View {
    @ObservedObject var model: CaptionMacModel
    @State private var window: NSWindow?

    var body: some View {
        ZStack {
            VStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(StatusWords.headline(for: model.state))
                        .font(.title2)
                        .fontWeight(.semibold)
                    if let detail = StatusWords.detail(for: model.state) {
                        Text(detail)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()

                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(model.stream.lines) { line in
                            HStack(alignment: .top, spacing: 8) {
                                if let speakerState = SpeakerLabeling.state(for: line), case .resolved(let speakerId) = speakerState {
                                    let palette = SpeakerPalette()
                                    let color = palette.colorForSpeaker(speakerId)
                                    Circle()
                                        .fill(color)
                                        .frame(width: 8, height: 8)
                                        .padding(.top, 4)
                                }
                                VStack(alignment: .leading, spacing: 4) {
                                    if case .resolved(let speakerId) = SpeakerLabeling.state(for: line) {
                                        Text(model.speakerNames.name(for: speakerId))
                                            .font(.caption)
                                            .fontWeight(.semibold)
                                            .foregroundColor(.secondary)
                                    }
                                    Text(line.displayText)
                                        .lineLimit(nil)
                                        .font(.system(.body, design: .monospaced))
                                        .foregroundColor(model.style.captionColor)
                                }
                                Spacer()
                            }
                        }
                    }
                    .padding()
                }
                .background(model.style.backgroundColor)

                HStack(spacing: 12) {
                    Spacer()
                    Button(action: toggleCaptions) {
                        Text(PrimaryControl.for(model.state).title)
                    }
                    .keyboardShortcut(.space, modifiers: [])
                }
                .padding()
            }
            .background(model.style.backgroundColor)
        }
        .onAppear {
            if let window = NSApplication.shared.windows.first(where: { $0.title == "Captions" }) {
                window.level = .floating
                window.isRestorable = true
            }
        }
    }

    private func toggleCaptions() {
        switch model.state {
        case .idle, .failed, .pausedQuiet:
            model.start()
        case .listening:
            model.stop()
        case .preparing:
            break
        }
    }
}
