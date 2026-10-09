import CaptionCore
import SwiftUI

extension RGBA {
    var color: Color { Color(red: r, green: g, blue: b, opacity: a) }
}

extension CaptionStyle {
    func font(for category: SystemTextSizeCategory, device: CaptionDeviceClass = .phone, scaled: Double = 1) -> Font {
        let design: Font.Design = switch font {
        case .system: .default
        case .rounded: .rounded
        case .serif: .serif
        case .monospaced: .monospaced
        }
        return .system(size: size.pointSize(for: category, device: device) * scaled, weight: .regular, design: design)
    }
}

/// One screen, three questions: which colors, how big, which lettering. A live preview sits on top.
struct SettingsSheet: View {
    @Binding var style: CaptionStyle
    let stream: CaptionStream
    let speakerNames: SpeakerNames
    let store: SavedConversationStoring?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var vocabularyText = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    preview
                    section("Colors") { presetRow }
                    section("Size") { sizeRow }
                    section("Lettering") { fontRow }
                    section("Words and names") { vocabularyRow }
                    section("Speaker labels") { speakerExplanationRow }
                    section("Conversation") { conversationRow }
                    section("Saved") { savedConversationsRow }
                    section("About") { aboutRow }
                }
                .padding()
                .foregroundStyle(style.text.color)
            }
            .containerBackground(style.background.color, for: .navigation)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() }.font(.headline) } }
        }
        .tint(style.text.color)
        .preferredColorScheme(style.background.isDark ? .dark : .light)
    }

    private var preview: some View {
        Text("Hello! This is how captions will look.")
            .font(style.font(for: SystemTextSizeCategory(dynamicTypeSize)))
            .foregroundStyle(style.text.color)
            .frame(maxWidth: .infinity, minHeight: 120, alignment: .leading)
            .padding()
            .background(style.background.color, in: RoundedRectangle(cornerRadius: 12))
            .accessibilityLabel("Preview of caption text")
    }

    private func section<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.title3.bold())
            content()
        }
    }

    private var presetRow: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 12)], spacing: 12) {
            ForEach(CaptionPreset.all) { preset in
                let selected = style.background == preset.background && style.text == preset.text
                Button { style = style.applying(preset) } label: {
                    VStack(spacing: 4) {
                        Text("Aa").font(.system(size: 34, weight: .bold)).foregroundStyle(preset.text.color)
                        Text(preset.name).font(.subheadline).foregroundStyle(preset.text.color)
                    }
                    .frame(maxWidth: .infinity, minHeight: 84)
                    .background(preset.background.color, in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(selected ? Color.accentColor : .secondary.opacity(0.4), lineWidth: selected ? 4 : 1))
                }
                .accessibilityLabel(preset.name + (selected ? ", selected" : ""))
            }
        }
    }

    private var sizeRow: some View {
        HStack(spacing: 16) {
            Button { style.size = style.size.smaller() } label: { Text("A−").font(.title2.bold()).frame(maxWidth: .infinity, minHeight: 56) }
                .buttonStyle(.bordered).disabled(style.size == .smallest).accessibilityLabel("Smaller text")
            Button { style.size = style.size.larger() } label: { Text("A+").font(.title2.bold()).frame(maxWidth: .infinity, minHeight: 56) }
                .buttonStyle(.bordered).disabled(style.size == .largest).accessibilityLabel("Larger text")
        }
    }

    private var fontRow: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 12)], spacing: 12) {
            ForEach(CaptionFont.allCases, id: \.self) { f in
                var sample = style; let _ = sample.font = f
                Button { style.font = f } label: {
                    Text(f.label).font(sample.font(for: SystemTextSizeCategory(dynamicTypeSize), scaled: 0.7)).frame(maxWidth: .infinity, minHeight: 56)
                }
                .buttonStyle(.bordered).tint(style.font == f ? .accentColor : .secondary)
            }
        }
    }

    private var vocabularyRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextEditor(text: $vocabularyText)
                .font(.body.monospaced())
                .frame(minHeight: 120)
                .border(Color.secondary.opacity(0.3), width: 1)
            Text(String(localized: "One word or name per line"))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .onAppear { vocabularyText = VocabularyStore().loadRawText() }
        .onChange(of: vocabularyText) { _, newValue in VocabularyStore().save(rawText: newValue) }
    }

    private var speakerExplanationRow: some View {
        Text(SpeakerExplanation.sentence)
            .font(.callout)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
    }

    private var conversationRow: some View {
        VStack(spacing: 12) {
            Button { copyPlainText() } label: {
                HStack {
                    Label(String(localized: "Copy all text"), systemImage: "doc.on.doc")
                    Spacer()
                }
                .frame(maxWidth: .infinity, minHeight: 56)
                .contentShape(Rectangle())
            }
            .buttonStyle(.bordered)
            .disabled(stream.lines.isEmpty)

            ShareLink(
                item: TranscriptFormatter.plainText(lines: stream.lines, speakerNames: speakerNames),
                subject: Text(String(localized: "Conversation")),
                label: { Label(String(localized: "Share as text"), systemImage: "square.and.arrow.up") }
            )
            .frame(maxWidth: .infinity, minHeight: 56)
            .buttonStyle(.bordered)
            .disabled(stream.lines.isEmpty)

            if let srtURL = createSRTFile() {
                ShareLink(
                    item: srtURL,
                    subject: Text(String(localized: "Conversation")),
                    label: { Label(String(localized: "Share as SRT file"), systemImage: "square.and.arrow.up") }
                )
                .frame(maxWidth: .infinity, minHeight: 56)
                .buttonStyle(.bordered)
            }
        }
    }

    private func copyPlainText() {
        UIPasteboard.general.string = TranscriptFormatter.plainText(lines: stream.lines, speakerNames: speakerNames)
    }

    private func createSRTFile() -> URL? {
        let srtText = TranscriptFormatter.srt(lines: stream.lines, speakerNames: speakerNames)
        guard !srtText.isEmpty else { return nil }

        let tmpURL = FileManager.default.temporaryDirectory.appendingPathComponent("Conversation.srt")
        do {
            try srtText.write(to: tmpURL, atomically: true, encoding: .utf8)
            return tmpURL
        } catch {
            return nil
        }
    }

    private var savedConversationsRow: some View {
        if let store = store {
            return AnyView(
                NavigationLink(destination: SavedConversationsView(store: store)) {
                    HStack {
                        Label(String(localized: "View conversations"), systemImage: "bubble.left.and.exclamation.bubble.right")
                        Spacer()
                        Image(systemName: "chevron.forward")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 56)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.bordered)
            )
        } else {
            return AnyView(
                HStack {
                    Label(String(localized: "View conversations"), systemImage: "bubble.left.and.exclamation.bubble.right")
                    Spacer()
                    Image(systemName: "chevron.forward")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 56)
                .contentShape(Rectangle())
                .buttonStyle(.bordered)
                .disabled(true)
            )
        }
    }

    private var aboutRow: some View {
        VStack(spacing: 12) {
            NavigationLink(destination: AboutCreditsView()) {
                HStack {
                    Label("Third-party credits", systemImage: "info.circle")
                    Spacer()
                    Image(systemName: "chevron.forward")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 56)
                .contentShape(Rectangle())
            }
            .buttonStyle(.bordered)

            // Guideline 5.1.1(i): the privacy policy must be reachable from inside the app. Both open in Safari.
            webLinkRow("Privacy policy", systemImage: "hand.raised", destination: SupportLinks.privacyPolicy)
            webLinkRow("Help and contact", systemImage: "questionmark.circle", destination: SupportLinks.support)
        }
    }

    private func webLinkRow(_ title: LocalizedStringKey, systemImage: String, destination: URL) -> some View {
        Link(destination: destination) {
            HStack {
                Label(title, systemImage: systemImage)
                Spacer()
                // Leaves the app: the arrow says so, unlike the chevron of a screen inside it.
                Image(systemName: "arrow.up.forward")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
            .frame(maxWidth: .infinity, minHeight: 56)
            .contentShape(Rectangle())
        }
        .buttonStyle(.bordered)
        .accessibilityHint(Text("Opens in Safari"))
    }
}
