import CaptionCore
import SwiftUI

/// Saved conversations on the one screen (#118, mock-up round2/02): the same background as everything else, plain rows
/// with one thin line between them, a plain underlined search line, and the delete questions asked in place in retro
/// words. "‹ Settings" fades back; a row fades into the conversation.
struct SavedConversationsPage: View {
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
            PageHeader(style: style, title: String(localized: "Saved"), backTitle: String(localized: "Settings"), onBack: onBack)
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

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PageHeader(style: style, title: conversation.map { SavedDates.title($0.savedAt) } ?? "",
                       backTitle: String(localized: "Saved"), onBack: onBack)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if let conversation {
                        Text(conversation.transcript)
                            .font(.body)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 18)
                            .textSelection(.enabled)
                        delete.padding(.top, 30)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 40)
            }
        }
        .foregroundStyle(style.text.color)
        .animation(.easeInOut(duration: 0.25), value: question)
        .task { conversation = (try? await store.all())?.first { $0.id == id } }
    }

    @ViewBuilder private var delete: some View {
        Group {
            if question.isAsking {
                InPlaceQuestionView(style: style,
                                    title: String(localized: "Delete this conversation?"),
                                    message: String(localized: "This can't be undone."),
                                    yes: String(localized: "Delete"), yesIsDestructive: true,
                                    no: String(localized: "Keep"),
                                    onYes: {
                                        if case .delete(let target) = question.confirm() {
                                            Task { try? await store.delete(id: target); onBack() }
                                        }
                                    },
                                    onNo: { question.keep() })
            } else {
                RetroWords(word: String(localized: "Delete"), color: mutedColor(style), background: style.background.color,
                           label: String(localized: "Delete this conversation")) { question.ask(.delete(id)) }
            }
        }
        .frame(maxWidth: .infinity)
        .transition(.opacity)
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
