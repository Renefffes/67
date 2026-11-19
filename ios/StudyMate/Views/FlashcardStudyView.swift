import SwiftData
import SwiftUI

struct FlashcardStudyView: View {
    let deck: Deck
    @State private var cards: [Flashcard] = []
    @State private var index = 0
    @State private var showingAnswer = false
    @State private var knownThisSession = 0
    @State private var finished = false

    var body: some View {
        Group {
            if cards.isEmpty {
                ContentUnavailableView("No flashcards", systemImage: "rectangle.on.rectangle.slash")
            } else if finished {
                summary
            } else {
                studyCard
            }
        }
        .padding()
        .navigationTitle("Flashcards")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { if cards.isEmpty { cards = deck.sortedCards } }
    }

    private var studyCard: some View {
        let card = cards[index]
        return VStack(spacing: 20) {
            VStack(spacing: 6) {
                Text("Card \(index + 1) of \(cards.count)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("cardCounter")
                ProgressView(value: Double(index), total: Double(cards.count))
            }

            Button {
                withAnimation(AppEnvironment.isUITesting ? nil : .spring(duration: 0.4)) { showingAnswer.toggle() }
            } label: {
                VStack(spacing: 12) {
                    Text(showingAnswer ? "ANSWER" : "QUESTION")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(showingAnswer ? .green : .indigo)
                    Text(showingAnswer ? card.back : card.front)
                        .font(.title3.weight(.semibold))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.primary)
                        .minimumScaleFactor(0.6)
                }
                .padding(24)
                .frame(maxWidth: .infinity, minHeight: 280)
                .background(
                    RoundedRectangle(cornerRadius: 24)
                        .fill(showingAnswer ? Color.green.opacity(0.12) : Color.indigo.opacity(0.12))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 24)
                        .strokeBorder(showingAnswer ? Color.green.opacity(0.4) : Color.indigo.opacity(0.4), lineWidth: 1.5)
                )
                .rotation3DEffect(.degrees(showingAnswer ? 360 : 0), axis: (x: 0, y: 1, z: 0))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("flashcard")
            .accessibilityLabel(showingAnswer ? card.back : card.front)
            .accessibilityHint("Double-tap to flip the card")

            Text(showingAnswer ? "Did you know it?" : "Tap the card to see the answer")
                .font(.footnote)
                .foregroundStyle(.secondary)

            HStack(spacing: 16) {
                Button { advance(known: false) } label: {
                    Label("Still learning", systemImage: "arrow.uturn.backward").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(.orange)
                .accessibilityIdentifier("stillLearningButton")

                Button { advance(known: true) } label: {
                    Label("Got it", systemImage: "checkmark").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .accessibilityIdentifier("gotItButton")
            }
            .controlSize(.large)
            Spacer()
        }
    }

    private var summary: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 64))
                .foregroundStyle(.green)
            Text("Session complete")
                .font(.title.bold())
                .accessibilityIdentifier("sessionComplete")
            Text("You knew \(knownThisSession) of \(cards.count) cards.")
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("sessionSummary")
            let missed = cards.filter { !$0.isKnown }
            if !missed.isEmpty {
                Button("Review the \(missed.count) I missed") { restart(with: missed) }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("reviewMissedButton")
            }
            Button("Study all again") { restart(with: deck.sortedCards) }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("studyAgainButton")
        }
    }

    private func advance(known: Bool) {
        cards[index].isKnown = known
        if known { knownThisSession += 1 }
        if index + 1 < cards.count {
            index += 1
            showingAnswer = false
        } else {
            finished = true
        }
    }

    private func restart(with newCards: [Flashcard]) {
        cards = newCards
        index = 0
        knownThisSession = 0
        showingAnswer = false
        finished = false
    }
}
