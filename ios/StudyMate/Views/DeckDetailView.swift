import SwiftData
import SwiftUI

struct DeckDetailView: View {
    @Bindable var deck: Deck
    private var isRegenerating: Bool { RegeneratingDecks.shared.ids.contains(deck.persistentModelID) }
    @State private var confirmingRegenerate = false

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Made with \(deck.engine)", systemImage: "sparkles")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("engineLabel")
                    if let note = deck.generationNote {
                        Text(note).font(.caption).foregroundStyle(.orange)
                    }
                    if !deck.cards.isEmpty {
                        ProgressView(value: Double(deck.knownCount), total: Double(deck.cards.count)) {
                            Text("\(deck.knownCount) of \(deck.cards.count) cards mastered").font(.caption)
                        }
                        .tint(.green)
                    }
                    if let score = deck.lastQuizScore, let total = deck.lastQuizTotal {
                        Text("Last quiz: \(score) / \(total)").font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }

            Section("Study") {
                NavigationLink {
                    FlashcardStudyView(deck: deck).readableWidth()
                } label: {
                    Label("Flashcards", systemImage: "rectangle.on.rectangle.angled")
                        .badge(deck.cards.count)
                }
                .accessibilityIdentifier("flashcardsLink")

                NavigationLink {
                    QuizView(deck: deck).readableWidth()
                } label: {
                    Label("Quiz", systemImage: "checklist")
                        .badge(deck.questions.count)
                }
                .accessibilityIdentifier("quizLink")

                NavigationLink {
                    TutorChatView(deck: deck).readableWidth()
                } label: {
                    Label("AI tutor", systemImage: "bubble.left.and.text.bubble.right")
                }
                .accessibilityIdentifier("tutorLink")
            }
            .disabled(isRegenerating)

            Section("Notes") {
                Text(deck.notes)
                    .font(.callout)
                    .textSelection(.enabled)
            }
        }
        .navigationTitle(deck.title)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button {
                        confirmingRegenerate = true
                    } label: {
                        Label("Regenerate cards and quiz", systemImage: "arrow.clockwise")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .disabled(isRegenerating)
            }
        }
        .confirmationDialog("Regenerate cards and quiz?", isPresented: $confirmingRegenerate, titleVisibility: .visible) {
            Button("Regenerate", role: .destructive) { Task { await regenerate() } }
        } message: {
            Text("Your current flashcards, including any edits and progress, and the quiz will be replaced.")
        }
        .overlay {
            if isRegenerating {
                ProgressView("Regenerating…")
                    .padding(24)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
            }
        }
    }

    private func regenerate() async {
        let id = deck.persistentModelID
        RegeneratingDecks.shared.ids.insert(id)
        defer { RegeneratingDecks.shared.ids.remove(id) }
        let outcome = await StudyAI.makeStudySet(notes: deck.notes, title: deck.title)
        deck.apply(outcome.set, engine: outcome.engine, note: outcome.note)
    }
}

extension View {
    /// Keeps study screens at a comfortable line length on iPad and in landscape.
    func readableWidth() -> some View {
        frame(maxWidth: 680).frame(maxWidth: .infinity)
    }
}

/// Decks with a regeneration in flight, kept outside the view so switching decks on iPad doesn't reset it.
@MainActor @Observable
final class RegeneratingDecks {
    static let shared = RegeneratingDecks()
    var ids: Set<PersistentIdentifier> = []
}
