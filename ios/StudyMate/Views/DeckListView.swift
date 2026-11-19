import SwiftData
import SwiftUI

struct DeckListView: View {
    @Query(sort: \Deck.createdAt, order: .reverse) private var decks: [Deck]
    @Environment(\.modelContext) private var context
    @State private var path: [Deck] = []
    @State private var showingNewDeck = false
    @State private var showingSettings = false

    var body: some View {
        NavigationStack(path: $path) {
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
                    List {
                        ForEach(decks) { deck in
                            NavigationLink(value: deck) { DeckRow(deck: deck) }
                        }
                        .onDelete { offsets in
                            offsets.map { decks[$0] }.forEach(context.delete)
                        }
                    }
                }
            }
            .navigationTitle("StudyMate")
            .navigationDestination(for: Deck.self) { DeckDetailView(deck: $0) }
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
                NewDeckView { deck in path = [deck] }
            }
            .sheet(isPresented: $showingSettings) { SettingsView() }
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
