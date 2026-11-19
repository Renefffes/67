import SwiftData
import SwiftUI

struct DeckListView: View {
    @Query(sort: \Deck.createdAt, order: .reverse) private var decks: [Deck]
    @Environment(\.modelContext) private var context
    @State private var selection: Deck?
    @State private var newDeck: NewDeckRequest?
    @State private var showingSettings = false
    @State private var settingsRevision = 0
    @State private var searchText = ""
    @State private var deckToDelete: Deck?

    private var filteredDecks: [Deck] {
        let query = searchText.trimmed
        guard !query.isEmpty else { return decks }
        return decks.filter { $0.title.localizedStandardContains(query) || $0.notes.localizedStandardContains(query) }
    }

    var body: some View {
        NavigationSplitView {
            Group {
                if decks.isEmpty {
                    FirstRunView(
                        onCreate: { openNewDeck(withSample: false) },
                        onSample: { openNewDeck(withSample: true) },
                        onSettings: { showingSettings = true }
                    )
                    .id(settingsRevision)
                } else {
                    List(selection: $selection) {
                        ForEach(filteredDecks) { deck in
                            NavigationLink(value: deck) { DeckRow(deck: deck) }
                                .contextMenu {
                                    Button("Delete deck", systemImage: "trash", role: .destructive) { deckToDelete = deck }
                                }
                        }
                        .onDelete { offsets in
                            deckToDelete = offsets.first.map { filteredDecks[$0] }
                        }
                    }
                    .searchable(text: $searchText, prompt: "Search decks")
                    .overlay {
                        if filteredDecks.isEmpty {
                            ContentUnavailableView.search(text: searchText)
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
                    Button { openNewDeck(withSample: false) } label: { Image(systemName: "plus") }
                        .accessibilityLabel("New deck")
                        .accessibilityIdentifier("newDeckButton")
                }
            }
            .sheet(item: $newDeck) { request in
                NewDeckView(startWithSample: request.startWithSample) { deck in selection = deck }
            }
            .sheet(isPresented: $showingSettings, onDismiss: { settingsRevision += 1 }) { SettingsView() }
            .confirmationDialog(
                "Delete “\(deckToDelete?.title ?? "")”?",
                isPresented: Binding(get: { deckToDelete != nil }, set: { if !$0 { deckToDelete = nil } }),
                titleVisibility: .visible,
                presenting: deckToDelete
            ) { deck in
                Button("Delete deck", role: .destructive) {
                    if selection == deck { selection = nil }
                    context.delete(deck)
                    try? context.save()
                }
                .accessibilityIdentifier("confirmDeleteDeckButton")
            } message: { _ in
                Text("Its flashcards, quiz results and tutor chat will be removed. This can't be undone.")
            }
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

    private func openNewDeck(withSample: Bool) {
        newDeck = NewDeckRequest(startWithSample: withSample)
    }
}

private struct NewDeckRequest: Identifiable {
    let id = UUID()
    let startWithSample: Bool
}

private struct FirstRunView: View {
    var onCreate: () -> Void
    var onSample: () -> Void
    var onSettings: () -> Void

    private var engine: AIEngine {
        StudyAI.effectiveEngine(StudyAI.storedEngine, hasGeminiKey: StudyAI.hasGeminiKey)
    }

    var body: some View {
        ViewThatFits(in: .vertical) {
            content
            ScrollView { content.padding(.vertical) }
        }
        .task { await StudyAI.checkAppleIntelligence() }
    }

    private var content: some View {
        ContentUnavailableView {
            Label("No study decks yet", systemImage: "books.vertical")
        } description: {
            Text("Paste or snap your notes and StudyMate turns them into flashcards, a quiz and a personal AI tutor.")
        } actions: {
            VStack(spacing: 12) {
                Button("Create your first deck", action: onCreate)
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("emptyStateNewDeckButton")
                Button("Try it with sample notes", systemImage: "wand.and.stars", action: onSample)
                    .accessibilityIdentifier("emptyStateSampleButton")
                engineHint
                    .padding(.top, 8)
            }
        }
    }

    @ViewBuilder private var engineHint: some View {
        if engine == .offline {
            VStack(spacing: 4) {
                Text("Works offline: cards are built from your notes without AI.")
                Button("Add a free Gemini key for AI cards", action: onSettings)
                    .foregroundStyle(.tint)
                    .accessibilityIdentifier("emptyStateSettingsButton")
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
        } else {
            Text("Cards are written by \(engine.displayName).")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}

private struct DeckRow: View {
    let deck: Deck
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(deck.title).font(.headline)
            let counts = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 2))
                : AnyLayout(HStackLayout(spacing: 12))
            counts {
                Label("\(deck.cards.count) cards", systemImage: "rectangle.on.rectangle")
                Label("\(deck.questions.count) questions", systemImage: "checklist")
            }
            .labelStyle(dynamicTypeSize.isAccessibilitySize ? AnyLabelStyle(.titleOnly) : AnyLabelStyle(.titleAndIcon))
            .fixedSize(horizontal: false, vertical: true)
            .font(.caption)
            .foregroundStyle(.secondary)
            if !deck.cards.isEmpty {
                ProgressView(value: Double(deck.knownCount), total: Double(deck.cards.count))
                    .tint(.green)
                    .accessibilityLabel("Mastered")
                    .accessibilityValue("\(deck.knownCount) of \(deck.cards.count) cards")
            }
        }
        .padding(.vertical, 4)
    }
}

private struct AnyLabelStyle: LabelStyle {
    private let make: (Configuration) -> AnyView
    init<S: LabelStyle>(_ style: S) { make = { AnyView(style.makeBody(configuration: $0)) } }
    func makeBody(configuration: Configuration) -> some View { make(configuration) }
}
