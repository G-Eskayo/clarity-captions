import CaptionCore
import SwiftUI

struct SavedConversationsView: View {
    @State private var conversations: [SavedConversation] = []
    @State private var searchText = ""
    @State private var selectedForDeletion: UUID?
    @State private var showDeleteAllAlert = false
    @Environment(\.dismiss) private var dismiss

    var filteredConversations: [SavedConversation] {
        SavedConversationSearch.matching(conversations, query: searchText)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                if conversations.isEmpty {
                    VStack(spacing: 16) {
                        Text(String(localized: "No saved conversations yet"))
                            .font(.headline)
                            .foregroundStyle(.secondary)
                        Text(String(localized: "Conversations are saved automatically when captioning stops"))
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding()
                } else if filteredConversations.isEmpty {
                    VStack(spacing: 16) {
                        Text(String(localized: "No results for \(searchText)"))
                            .font(.headline)
                            .foregroundStyle(.secondary)
                    }
                    .padding()
                } else {
                    List {
                        ForEach(filteredConversations) { conversation in
                            NavigationLink(destination: ConversationDetailView(conversation: conversation)) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(dateLabel(for: conversation.date))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Text(conversation.text)
                                        .lineLimit(2)
                                        .foregroundStyle(.primary)
                                }
                            }
                            .swipeActions {
                                Button(role: .destructive) {
                                    selectedForDeletion = conversation.id
                                } label: {
                                    Label(String(localized: "Delete"), systemImage: "trash")
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle(String(localized: "Saved Conversations"))
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "Search")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    if !conversations.isEmpty {
                        Menu {
                            Button(role: .destructive) {
                                showDeleteAllAlert = true
                            } label: {
                                Label(String(localized: "Delete All"), systemImage: "trash.fill")
                            }
                        } label: {
                            Image(systemName: "ellipsis")
                        }
                    }
                }
            }
            .onAppear { loadConversations() }
            .confirmationDialog(
                "Delete conversation?",
                isPresented: Binding(
                    get: { selectedForDeletion != nil },
                    set: { if !$0 { selectedForDeletion = nil } }
                )
            ) {
                Button(String(localized: "Delete"), role: .destructive) {
                    if let id = selectedForDeletion {
                        deleteConversation(id: id)
                    }
                }
            } message: {
                Text(String(localized: "This can't be undone."))
            }
            .confirmationDialog(
                "Delete all conversations?",
                isPresented: $showDeleteAllAlert
            ) {
                Button(String(localized: "Delete All"), role: .destructive) {
                    deleteAllConversations()
                }
            } message: {
                Text(String(localized: "This can't be undone."))
            }
        }
    }

    private func loadConversations() {
        conversations = SavedConversationStore().all()
    }

    private func deleteConversation(id: UUID) {
        do {
            try SavedConversationStore().delete(id: id)
            loadConversations()
            selectedForDeletion = nil
        } catch {
            print("Failed to delete conversation: \(error)")
        }
    }

    private func deleteAllConversations() {
        do {
            try SavedConversationStore().deleteAll()
            loadConversations()
            showDeleteAllAlert = false
        } catch {
            print("Failed to delete all conversations: \(error)")
        }
    }

    private func dateLabel(for date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

struct ConversationDetailView: View {
    let conversation: SavedConversation

    var body: some View {
        ScrollView {
            Text(conversation.text)
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle("Conversation")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                ShareLink(item: conversation.text) {
                    Image(systemName: "square.and.arrow.up")
                }
            }
        }
    }
}
