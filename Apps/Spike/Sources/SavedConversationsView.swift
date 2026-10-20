import CaptionCore
import SwiftUI
import UniformTypeIdentifiers

/// Saved conversations on the one screen (#118, mock-up round2/02): the same background as everything else, plain rows
/// with one thin line between them, a plain underlined search line, and the delete questions asked in place in retro
/// words. "‹ Settings" fades back; a row fades into the conversation.
struct SavedConversationsPage: View {
    /// "Settings", or "Captions" when it was opened from the list icon on the main screen (#137).
    var backTitle: String = String(localized: "Settings")
    let store: SavedConversationStoring
    let style: CaptionStyle
    let onBack: () -> Void
    let onOpen: (UUID) -> Void
    @State private var conversations: [SavedConversation] = []
    @State private var searchText = ""
    @State private var loaded = false
    @State private var question = InPlaceQuestion<SavedListQuestion>()

    private var filteredConversations: [SavedConversation] {
        SavedConversationSearch.filter(conversations, query: searchText)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PageHeader(style: style, title: String(localized: "Saved"), backTitle: backTitle, onBack: onBack)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Kept for 30 days, then deleted.")
                        .font(.body)
                        .foregroundStyle(mutedColor(style))
                        .padding(.top, 18)
                    if loaded && conversations.isEmpty {
                        emptyState
                    } else {
                        searchLine
                        ForEach(filteredConversations) { conversation in
                            Button { onOpen(conversation.id) } label: { row(conversation) }
                                .buttonStyle(.plain)
                            ThinRule(style: style)
                        }
                        if !conversations.isEmpty { deleteAll.padding(.top, 26) }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 40)
            }
        }
        .foregroundStyle(style.text.color)
        .animation(.easeInOut(duration: 0.25), value: question)
        .task {
            await load()
            if DemoMode.settingsPush == "deleteall" { question.ask(.deleteAll) }   // debug only: the UI audit
            if DemoMode.flow == "delete" {
                // Debug only (#118 recording): [ Delete all ] asks in place, [ Keep ] answers no.
                try? await Task.sleep(for: .seconds(2)); question.ask(.deleteAll)
                try? await Task.sleep(for: .seconds(3)); question.keep()
            }
        }
    }

    private var emptyState: some View {
        Text("Conversations you save show up here.")
            .font(.body)
            .foregroundStyle(mutedColor(style))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 24)
    }

    private var searchLine: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField(String(localized: "Search"), text: $searchText)
                .font(.body)
                .textInputAutocapitalization(.never)
                .submitLabel(.search)
            ThinRule(style: style)
        }
        .padding(.top, 22)
    }

    private func row(_ conversation: SavedConversation) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(SavedDates.title(conversation.savedAt))
                .font(.headline.weight(.heavy))
            Text(SavedDates.preview(conversation.transcript))
                .font(.body)
                .foregroundStyle(mutedColor(style))
                .lineLimit(2)
                .multilineTextAlignment(.leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 14)
        .contentShape(Rectangle())
    }

    @ViewBuilder private var deleteAll: some View {
        Group {
            if question.asking == .deleteAll {
                InPlaceQuestionView(style: style,
                                    title: String(format: String(localized: "Delete all %lld conversations?"), conversations.count),
                                    message: String(localized: "This can't be undone."),
                                    yes: String(localized: "Delete all"), yesIsDestructive: true,
                                    no: String(localized: "Keep"),
                                    onYes: { if question.confirm() == .deleteAll { Task { try? await store.deleteAll(); await load() } } },
                                    onNo: { question.keep() })
            } else {
                RetroWords(word: String(localized: "Delete all"), color: mutedColor(style), background: style.background.color,
                           label: String(localized: "Delete all saved conversations")) { question.ask(.deleteAll) }
            }
        }
        .frame(maxWidth: .infinity)
        .transition(.opacity)
    }

    private func load() async {
        conversations = (try? await store.all()) ?? []
        loaded = true
    }
}

/// One saved conversation, on the same screen: "‹ Saved", its words (selectable), and [ Delete ] asked in place.
struct SavedConversationPage: View {
    let store: SavedConversationStoring
    let id: UUID
    let style: CaptionStyle
    let onBack: () -> Void
    @State private var conversation: SavedConversation?
    @State private var question = InPlaceQuestion<SavedListQuestion>()
    // Opens like a paused conversation (owner, #139): dimmed, [ Share ] over [ Delete ]. Debug flags start it clear.
    @State private var veil = SavedConversationVeil()
    @State private var showingHint = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private static let hintKey = "savedVeilHintCount"
    private var veilAnimation: Animation { .easeInOut(duration: reduceMotion ? 0.2 : 0.35) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PageHeader(style: style, title: conversation.map { SavedDates.title($0.savedAt) } ?? "",
                       backTitle: String(localized: "Saved"), onBack: onBack)
            GeometryReader { geo in
                ZStack {
                    ScrollView {
                        if let conversation {
                            SavedTranscriptText(transcript: conversation.transcript, style: style,
                                                minHeight: max(0, geo.size.height - 58), dimmed: veil.isVisible,
                                                onHoldEmptySpace: bringBackVeil)
                                .padding(.top, 18)
                                .padding(.horizontal, 8)
                                .padding(.bottom, 40)
                        }
                    }
                    if veil.isVisible, conversation != nil { veilLayer.transition(.opacity) }
                    if showingHint {
                        // Same look as the paused screen's hint; shown the first time the dim is cleared, ever.
                        Text(String(localized: "Hold words to copy. Hold empty space to bring back Share and Delete."))
                            .font(.footnote.weight(.semibold))
                            .multilineTextAlignment(.center)
                            .foregroundStyle(style.background.color)
                            .padding(.horizontal, 16).padding(.vertical, 10)
                            .background(style.text.color, in: Capsule())
                            .padding(.horizontal, 16)
                            .frame(maxHeight: .infinity, alignment: .bottom)
                            .padding(.bottom, 24)
                            .allowsHitTesting(false)
                            .transition(.opacity)
                    }
                }
            }
        }
        .foregroundStyle(style.text.color)
        .animation(.easeInOut(duration: 0.25), value: question)
        .task {
            conversation = (try? await store.all())?.first { $0.id == id }
            if DemoMode.veilCleared || DemoMode.select { _ = veil.tap(hintsShownBefore: 1) }
            if DemoMode.veilCleared { showingHint = true }
        }
    }

    /// The dim over the words (about 86% of the theme's background, as on a paused conversation) with [ Share ] over
    /// [ Delete ], centered. One tap on the dim clears it; a tap while Delete is asking answers it like [ Keep ].
    private var veilLayer: some View {
        ZStack {
            style.background.color.opacity(0.86)
                .contentShape(Rectangle())
                .onTapGesture { clearVeil() }
                .accessibilityElement()
                .accessibilityLabel(String(localized: "Saved conversation"))
                .accessibilityAddTraits(.isButton)
                .accessibilityHint(String(localized: "Double tap to show the conversation"))
            if question.isAsking {
                InPlaceQuestionView(style: style,
                                    title: String(localized: "Delete this conversation?"),
                                    message: String(localized: "This can't be undone."),
                                    yes: String(localized: "Delete"), yesIsDestructive: true,
                                    no: String(localized: "Keep"), stacked: true,
                                    onYes: {
                                        if case .delete(let target) = question.confirm() {
                                            Task { try? await store.delete(id: target); onBack() }
                                        }
                                    },
                                    onNo: { question.keep() })
                    .transition(.opacity)
            } else {
                VStack(spacing: 24) {
                    if let conversation, SavedConversationExport.canShare(conversation) {
                        // #139: Apple's share sheet, the one exception on this page. Notes gets the text; Files a .txt.
                        ShareLink(item: SavedTranscript(conversation: conversation),
                                  preview: SharePreview(SavedConversationExport.fileName(for: conversation))) {
                            RetroWordsText(word: String(localized: "Share"), color: style.text.color,
                                           background: style.background.color)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(String(localized: "Share this conversation"))
                    }
                    RetroWords(word: String(localized: "Delete"), color: style.text.color, background: style.background.color,
                               label: String(localized: "Delete this conversation")) { question.ask(.delete(id)) }
                }
                .transition(.opacity)
            }
        }
    }

    private func clearVeil() {
        let hintsShown = UserDefaults.standard.integer(forKey: Self.hintKey)
        withAnimation(veilAnimation) {
            question.keep()
            if veil.tap(hintsShownBefore: hintsShown) {
                UserDefaults.standard.set(hintsShown + 1, forKey: Self.hintKey)
                showingHint = true
            }
        }
    }

    private func bringBackVeil() {
        withAnimation(veilAnimation) {
            veil.holdOnEmptySpace()
            showingHint = false
        }
    }
}

/// A saved conversation as [ Share ] hands it out (#139): plain text first, so Notes and Messages paste it inline,
/// then a dated .txt for Files and AirDrop.
struct SavedTranscript: Transferable {
    let conversation: SavedConversation

    static var transferRepresentation: some TransferRepresentation {
        ProxyRepresentation { SavedConversationExport.text(for: $0.conversation) }
        DataRepresentation(exportedContentType: .plainText) { SavedConversationExport.data(for: $0.conversation) }
            .suggestedFileName { SavedConversationExport.fileName(for: $0.conversation) }
    }
}

/// How a saved conversation is named in the list (mock-up round2/02): "Today, 8:56 AM", "Yesterday, 7:12 PM", then dates.
enum SavedDates {
    static func title(_ date: Date, now: Date = Date(), calendar: Calendar = .current) -> String {
        let time = date.formatted(date: .omitted, time: .shortened)
        if calendar.isDate(date, inSameDayAs: now) { return String(format: String(localized: "Today, %@"), time) }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(date, inSameDayAs: yesterday) {
            return String(format: String(localized: "Yesterday, %@"), time)
        }
        return date.formatted(date: .abbreviated, time: .shortened)
    }

    static func preview(_ transcript: String) -> String {
        let flat = transcript.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        return flat.count > 70 ? String(flat.prefix(70)).trimmingCharacters(in: .whitespaces) + "…" : flat
    }
}
