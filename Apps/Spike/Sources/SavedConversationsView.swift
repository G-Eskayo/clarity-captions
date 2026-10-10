import CaptionCore
import SwiftUI

struct SavedConversationsView: View {
    let store: SavedConversationStoring
    @State private var conversations: [SavedConversation] = []
    @State private var searchText = ""
    @State private var isLoading = false
    @Environment(\.dismiss) private var dismiss
    @State private var confirmDeleteOne: SavedConversation?
    @State private var confirmDeleteAll = false

    private var filteredConversations: [SavedConversation] {
        SavedConversationSearch.filter(conversations, query: searchText)
    }

    var body: some View {
        NavigationStack {
            Group {
                if conversations.isEmpty {
                    emptyState
                } else {
                    list
                }
            }
            .navigationTitle("Saved conversations")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if !conversations.isEmpty {
                        Menu {
                            Button(role: .destructive) {
                                confirmDeleteAll = true
                            } label: {
                                Label(String(localized: "Delete all"), systemImage: "trash")
                            }
                        } label: {
                            Image(systemName: "ellipsis")
                        }
                    }
                }
            }
            .task {
                await loadConversations()
                if DemoMode.settingsPush == "deleteall" { confirmDeleteAll = true }   // debug only: the UI audit
            }
        }
        .confirmationDialog(
            String(localized: "Delete conversation?"),
            isPresented: Binding(
                get: { confirmDeleteOne != nil },
                set: { if !$0 { confirmDeleteOne = nil } }
            ),
            presenting: confirmDeleteOne
        ) { conversation in
            Button(String(localized: "Delete"), role: .destructive) {
                Task {
                    await deleteConversation(conversation)
                }
            }
        } message: { _ in
            Text(String(localized: "This can't be undone."))
        }
        .confirmationDialog(
            String(localized: "Delete all conversations?"),
            isPresented: $confirmDeleteAll
        ) {
            Button(String(localized: "Delete all"), role: .destructive) {
                Task {
                    await deleteAllConversations()
                }
            }
        } message: {
            Text(String(localized: "This can't be undone."))
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Text(String(localized: "No saved conversations yet"))
                .font(.headline)
                .foregroundStyle(.secondary)
            Text(String(localized: "Conversations will save automatically after each session."))
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .padding()
    }

    private var list: some View {
        List {
            ForEach(filteredConversations) { conversation in
                NavigationLink(destination: detailView(for: conversation)) {
                    conversationRow(conversation)
                }
            }
            .onDelete(perform: deleteRows)
        }
        .searchable(text: $searchText, prompt: String(localized: "Search conversations"))
    }

    private func conversationRow(_ conversation: SavedConversation) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(formatDate(conversation.savedAt))
                .font(.headline)
            Text(conversation.transcript.prefix(60).trimmingCharacters(in: .whitespacesAndNewlines))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
    }

    private func detailView(for conversation: SavedConversation) -> some View {
        ScrollView {
            Text(conversation.transcript)
                .font(.body)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .textSelection(.enabled)
        }
        .navigationTitle(formatDate(conversation.savedAt))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private func deleteRows(at offsets: IndexSet) {
        for index in offsets {
            confirmDeleteOne = filteredConversations[index]
        }
    }

    private func loadConversations() async {
        isLoading = true
        do {
            conversations = try await store.all()
        } catch {
            // Silent fail: if load fails, show empty state
        }
        isLoading = false
    }

    private func deleteConversation(_ conversation: SavedConversation) async {
        do {
            try await store.delete(id: conversation.id)
            await loadConversations()
        } catch {
            // Silent fail: if delete fails, keep the state as-is
        }
    }

    private func deleteAllConversations() async {
        do {
            try await store.deleteAll()
            await loadConversations()
        } catch {
            // Silent fail: if delete fails, keep the state as-is
        }
    }
}
