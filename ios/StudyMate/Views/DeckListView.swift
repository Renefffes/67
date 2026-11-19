import SwiftData
import SwiftUI

struct DeckListView: View {
    @Query(sort: \Deck.createdAt, order: .reverse) private var decks: [Deck]
    @Environment(\.modelContext) private var context
    @State private var selection: Deck?
    @State private var showingNewDeck = false
    @State private var showingSettings = false

    var body: some View {
        NavigationSplitView {
            Group {
                if decks.isEmpty {
                    ContentUnavailableView {
                        Label("No study decks yet", systemImage: "books.vertical")
                    } description: {
                        Text("Paste or snap your notes and StudyMate turns them into flashcards, a quiz and a personal AI tutor.")
                    } actions: {
                        Button("Create your first deck") { showingNewDeck = true }
                            .buttonStyle(.borderedProminent)
                            .accessibilityIdentifier("emptyStateNewDeckButton")
                    }
                } else {
                    List(selection: $selection) {
                        ForEach(decks) { deck in
                            NavigationLink(value: deck) { DeckRow(deck: deck) }
                        }
                        .onDelete { offsets in
                            let removed = offsets.map { decks[$0] }
                            if let selected = selection, removed.contains(selected) { selection = nil }
                            removed.forEach(context.delete)
                        }
                    }
                }
            }
            .navigationTitle("StudyMate")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showingSettings = true } label: { Image(systemName: "gearshape") }
                        .accessibilityLabel("Settings")
                        .accessibilityIdentifier("settingsButton")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingNewDeck = true } label: { Image(systemName: "plus") }
                        .accessibilityLabel("New deck")
                        .accessibilityIdentifier("newDeckButton")
                }
            }
            .sheet(isPresented: $showingNewDeck) {
                NewDeckView { deck in selection = deck }
            }
            .sheet(isPresented: $showingSettings) { SettingsView() }
        } detail: {
            if let deck = selection {
                NavigationStack { DeckDetailView(deck: deck) }
                    .id(deck.persistentModelID)
            } else {
                ContentUnavailableView(
                    decks.isEmpty ? "Add your notes to start" : "Pick a deck",
                    systemImage: "rectangle.on.rectangle.angled",
                    description: Text(decks.isEmpty
                        ? "Tap + to paste, photograph or scan your notes."
                        : "Choose a deck in the sidebar to study its flashcards, take the quiz or ask the tutor.")
                )
            }
        }
    }
}

private struct DeckRow: View {
    let deck: Deck

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(deck.title).font(.headline)
            HStack(spacing: 12) {
                Label("\(deck.cards.count) cards", systemImage: "rectangle.on.rectangle")
                Label("\(deck.questions.count) questions", systemImage: "checklist")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            if !deck.cards.isEmpty {
                ProgressView(value: Double(deck.knownCount), total: Double(deck.cards.count))
                    .tint(.green)
            }
        }
        .padding(.vertical, 4)
    }
}
