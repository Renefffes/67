import SwiftData
import SwiftUI

struct FlashcardStudyView: View {
    let deck: Deck
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var queue: [Flashcard] = []
    @State private var index = 0
    @State private var phase: Phase = .notStarted
    @State private var showingAnswer = false
    @State private var knownThisSession = 0
    @State private var history: [Step] = []
    @State private var dragOffset: CGSize = .zero
    @State private var isDragging = false
    @State private var lastSwipeEnded = Date.distantPast
    @State private var editingCard: Flashcard?
    @State private var addingCard = false
    @State private var showingCardList = false
    @State private var confirmingDelete = false
    @State private var confirmingReset = false

    private enum Phase { case notStarted, studying, finished, allMastered }

    private struct Step {
        let card: Flashcard
        let index: Int
        let wasKnown: Bool
        let previousReviewDate: Date?
        let markedKnown: Bool
    }

    private static let swipeThreshold: CGFloat = 100

    private var currentCard: Flashcard? {
        phase == .studying && queue.indices.contains(index) ? queue[index] : nil
    }

    var body: some View {
        Group {
            if deck.cards.isEmpty {
                emptyState
            } else {
                switch phase {
                case .notStarted: Color.clear
                case .studying: if let card = currentCard { studyCard(card) }
                case .finished: summary
                case .allMastered: allMastered
                }
            }
        }
        .padding()
        .navigationTitle("Flashcards")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbar }
        .background(BackSwipeBlocker())
        .onAppear { if phase == .notStarted { startSession(with: Self.cardsToReview(in: deck)) } }
        .sheet(item: $editingCard) { card in
            CardEditorView(title: "Edit card", front: card.front, back: card.back) { front, back in
                card.front = front
                card.back = back
            }
        }
        .sheet(isPresented: $addingCard) {
            CardEditorView(title: "New card", front: "", back: "") { front, back in addCard(front: front, back: back) }
        }
        .sheet(isPresented: $showingCardList) {
            CardListView(deck: deck, onAdd: addCard, onDelete: delete)
        }
        .confirmationDialog("Delete this card?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete card", role: .destructive) { if let card = currentCard { delete(card) } }
                .accessibilityIdentifier("confirmDeleteCardButton")
        } message: {
            Text("It will be removed from this deck for good.")
        }
        .confirmationDialog("Reset progress?", isPresented: $confirmingReset, titleVisibility: .visible) {
            Button("Reset progress", role: .destructive) { resetProgress() }
                .accessibilityIdentifier("confirmResetButton")
        } message: {
            Text("All cards go back to Still learning so you can start fresh.")
        }
    }

    // MARK: Study

    private func studyCard(_ card: Flashcard) -> some View {
        VStack(spacing: 20) {
            VStack(spacing: 6) {
                Text("Card \(index + 1) of \(queue.count)")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("cardCounter")
                ProgressView(value: Double(index), total: Double(queue.count))
                deckProgress
            }

            Button {
                guard !isDragging, Date.now.timeIntervalSince(lastSwipeEnded) > 0.4 else { return }
                withAnimation(AppEnvironment.isUITesting ? nil : .easeInOut(duration: 0.35)) { showingAnswer.toggle() }
            } label: {
                ZStack {
                    CardFace(label: "QUESTION", text: card.front, tint: .indigo)
                        .opacity(showingAnswer ? 0 : 1)
                        .animation(faceSwapAnimation, value: showingAnswer)
                        .rotation3DEffect(.degrees(showingAnswer ? 180 : 0), axis: (x: 0, y: 1, z: 0), perspective: 0.4)
                    CardFace(label: "ANSWER", text: card.back, tint: .green)
                        .opacity(showingAnswer ? 1 : 0)
                        .animation(faceSwapAnimation, value: showingAnswer)
                        .rotation3DEffect(.degrees(showingAnswer ? 0 : -180), axis: (x: 0, y: 1, z: 0), perspective: 0.4)
                }
                .overlay(alignment: .top) { swipeBadge }
            }
            .buttonStyle(.plain)
            .offset(x: dragOffset.width, y: dragOffset.height * 0.2)
            .rotationEffect(.degrees(Double(dragOffset.width / 25)))
            .simultaneousGesture(swipeGesture)
            .id(ObjectIdentifier(card))
            .accessibilityIdentifier("flashcard")
            .accessibilityLabel(showingAnswer ? card.back : card.front)
            .accessibilityHint("Double-tap to flip the card. Swipe right if you knew it, left if you're still learning.")
            .accessibilityAction(named: "Got it") { advance(known: true) }
            .accessibilityAction(named: "Still learning") { advance(known: false) }

            Text(showingAnswer ? "Did you know it? Swipe right if yes, left if not." : "Tap the card to see the answer")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

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
            Spacer(minLength: 0)
        }
    }

    private var deckProgress: some View {
        let known = deck.knownCount
        return Text("\(known) mastered · \(deck.cards.count - known) still learning")
            .font(.caption)
            .foregroundStyle(.secondary)
            .accessibilityIdentifier("deckProgress")
    }

    private var faceSwapAnimation: Animation? {
        AppEnvironment.isUITesting ? nil : .linear(duration: 0.01).delay(0.17)
    }

    @ViewBuilder private var swipeBadge: some View {
        let width = dragOffset.width
        if abs(width) > 20 {
            let known = width > 0
            Text(known ? "GOT IT" : "STILL LEARNING")
                .font(.headline.weight(.heavy))
                .foregroundStyle(known ? .green : .orange)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .overlay(Capsule().strokeBorder(known ? Color.green : Color.orange, lineWidth: 2))
                .background(.background, in: Capsule())
                .padding(.top, 16)
                .opacity(min(1, Double(abs(width) - 20) / 60))
                .accessibilityHidden(true)
        }
    }

    private var swipeGesture: some Gesture {
        DragGesture(minimumDistance: 15)
            .onChanged { value in
                guard abs(value.translation.width) > abs(value.translation.height) || dragOffset != .zero else { return }
                isDragging = true
                dragOffset = value.translation
            }
            .onEnded { value in
                isDragging = false
                lastSwipeEnded = .now
                let distance = value.translation.width + (value.predictedEndTranslation.width - value.translation.width) * 0.25
                guard dragOffset != .zero, abs(distance) > Self.swipeThreshold else {
                    withAnimation(.spring(duration: 0.3)) { dragOffset = .zero }
                    return
                }
                let known = distance > 0
                if AppEnvironment.isUITesting {
                    dragOffset = .zero
                    advance(known: known)
                    return
                }
                let swipedCard = currentCard
                withAnimation(.easeIn(duration: 0.2)) { dragOffset.width = known ? 600 : -600 }
                Task {
                    try? await Task.sleep(for: .milliseconds(200))
                    dragOffset = .zero
                    guard let swipedCard, currentCard === swipedCard else { return }
                    advance(known: known)
                }
            }
    }

    // MARK: Summary

    private var summary: some View {
        let missed = queue.filter { !$0.isKnown }
        return VStack(spacing: 16) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 64))
                .foregroundStyle(.green)
            Text("Session complete")
                .font(.title.bold())
                .accessibilityIdentifier("sessionComplete")
            Text("You knew \(knownThisSession) of \(Self.cardCount(queue.count)).")
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("sessionSummary")
            deckProgress
            if !missed.isEmpty {
                Button("Review the \(missed.count) I missed") { startSession(with: missed) }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("reviewMissedButton")
            }
            Button("Study all again") { startSession(with: deck.sortedCards) }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("studyAgainButton")
            Button("Done") { dismiss() }
                .accessibilityIdentifier("doneStudyingButton")
        }
        .frame(maxHeight: .infinity)
    }

    private var allMastered: some View {
        VStack(spacing: 16) {
            Image(systemName: "star.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.yellow)
            Text("All cards mastered")
                .font(.title.bold())
                .accessibilityIdentifier("allMastered")
            Text("You know all \(Self.cardCount(deck.cards.count)) in this deck. Study them again to keep them fresh.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Button("Study all again") { startSession(with: deck.sortedCards) }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("studyAgainButton")
            Button("Reset progress", role: .destructive) { confirmingReset = true }
                .buttonStyle(.bordered)
        }
        .frame(maxHeight: .infinity)
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No flashcards", systemImage: "rectangle.on.rectangle.slash")
        } description: {
            Text("Add your own cards, or regenerate them from your notes on the deck page.")
        } actions: {
            Button("Add a card") { addingCard = true }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("emptyAddCardButton")
        }
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            if phase == .studying || phase == .finished {
                Button { undo() } label: { Image(systemName: "arrow.uturn.backward.circle") }
                    .accessibilityLabel("Undo last card")
                    .accessibilityIdentifier("undoButton")
                    .disabled(history.isEmpty)
            }
            Menu {
                if let card = currentCard {
                    Button { editingCard = card } label: { Label("Edit this card", systemImage: "pencil") }
                        .accessibilityIdentifier("editCardButton")
                    Button(role: .destructive) { confirmingDelete = true } label: {
                        Label("Delete this card", systemImage: "trash")
                    }
                    .accessibilityIdentifier("deleteCardButton")
                    Divider()
                }
                Button { addingCard = true } label: { Label("Add a card", systemImage: "plus") }
                    .accessibilityIdentifier("addCardButton")
                Button { showingCardList = true } label: { Label("All cards", systemImage: "list.bullet") }
                    .accessibilityIdentifier("allCardsButton")
                if phase == .studying, queue.count - index > 1 {
                    Button { shuffleRemaining() } label: { Label("Shuffle remaining", systemImage: "shuffle") }
                        .accessibilityIdentifier("shuffleButton")
                }
                if deck.knownCount > 0 {
                    Button(role: .destructive) { confirmingReset = true } label: {
                        Label("Reset progress", systemImage: "arrow.counterclockwise")
                    }
                    .accessibilityIdentifier("resetProgressButton")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .accessibilityLabel("Card options")
            .accessibilityIdentifier("cardOptionsButton")
        }
    }

    // MARK: Actions

    /// Cards still being learned, the ones never studied first, then the ones studied longest ago.
    static func cardsToReview(in deck: Deck) -> [Flashcard] {
        deck.cards.filter { !$0.isKnown }.sorted { a, b in
            switch (a.lastReviewedAt, b.lastReviewedAt) {
            case (nil, nil): a.order < b.order
            case (nil, _): true
            case (_, nil): false
            case let (x?, y?): x == y ? a.order < b.order : x < y
            }
        }
    }

    private static func cardCount(_ count: Int) -> String {
        count == 1 ? "1 card" : "\(count) cards"
    }

    private func startSession(with cards: [Flashcard]) {
        queue = cards
        index = 0
        knownThisSession = 0
        history = []
        showingAnswer = false
        dragOffset = .zero
        phase = cards.isEmpty ? (deck.cards.isEmpty ? .studying : .allMastered) : .studying
    }

    private func advance(known: Bool) {
        guard let card = currentCard else { return }
        history.append(Step(card: card, index: index, wasKnown: card.isKnown, previousReviewDate: card.lastReviewedAt, markedKnown: known))
        card.isKnown = known
        card.lastReviewedAt = .now
        if known { knownThisSession += 1 }
        showingAnswer = false
        if index + 1 < queue.count {
            index += 1
        } else {
            phase = .finished
        }
    }

    private func undo() {
        guard let step = history.popLast() else { return }
        step.card.isKnown = step.wasKnown
        step.card.lastReviewedAt = step.previousReviewDate
        if step.markedKnown { knownThisSession -= 1 }
        index = queue.firstIndex { $0 === step.card } ?? min(step.index, max(queue.count - 1, 0))
        showingAnswer = false
        phase = .studying
    }

    private func shuffleRemaining() {
        guard index < queue.count else { return }
        queue.replaceSubrange((index + 1)..<queue.count, with: queue[(index + 1)...].shuffled())
    }

    private func addCard(front: String, back: String) {
        let card = Flashcard(front: front, back: back, order: (deck.cards.map(\.order).max() ?? -1) + 1)
        deck.cards.append(card)
        switch phase {
        case .studying: queue.append(card)
        case .notStarted, .finished, .allMastered: startSession(with: [card])
        }
    }

    private func delete(_ card: Flashcard) {
        if let position = queue.firstIndex(where: { $0 === card }) {
            queue.remove(at: position)
            if position < index { index -= 1 }
        }
        history.removeAll { $0.card === card }
        deck.cards.removeAll { $0 === card }
        context.delete(card)
        showingAnswer = false
        if phase == .studying, index >= queue.count {
            if queue.isEmpty && history.isEmpty {
                startSession(with: Self.cardsToReview(in: deck))
            } else {
                phase = .finished
            }
        }
    }

    private func resetProgress() {
        for card in deck.cards {
            card.isKnown = false
            card.lastReviewedAt = nil
        }
        startSession(with: deck.sortedCards)
    }
}

private struct CardFace: View {
    let label: String
    let text: String
    let tint: Color

    var body: some View {
        VStack(spacing: 12) {
            Text(label)
                .font(.caption.weight(.bold))
                .foregroundStyle(tint)
            ScrollView {
                Text(text)
                    .font(.title3.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity)
            }
            .scrollBounceBehavior(.basedOnSize)
            .frame(maxHeight: 320)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(24)
        .frame(maxWidth: .infinity, minHeight: 280)
        .background(RoundedRectangle(cornerRadius: 24).fill(tint.opacity(0.12)))
        .background(RoundedRectangle(cornerRadius: 24).fill(.background))
        .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(tint.opacity(0.4), lineWidth: 1.5))
    }
}

struct CardEditorView: View {
    let title: String
    var onSave: (String, String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var front: String
    @State private var back: String

    init(title: String, front: String, back: String, onSave: @escaping (String, String) -> Void) {
        self.title = title
        self.onSave = onSave
        _front = State(initialValue: front)
        _back = State(initialValue: back)
    }

    private var canSave: Bool { !front.trimmed.isEmpty && !back.trimmed.isEmpty }

    var body: some View {
        NavigationStack {
            Form {
                Section("Question") {
                    TextField("Front of the card", text: $front, axis: .vertical)
                        .lineLimit(2...6)
                        .accessibilityIdentifier("cardFrontField")
                }
                Section("Answer") {
                    TextField("Back of the card", text: $back, axis: .vertical)
                        .lineLimit(2...8)
                        .accessibilityIdentifier("cardBackField")
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(front.trimmed, back.trimmed)
                        dismiss()
                    }
                    .disabled(!canSave)
                    .accessibilityIdentifier("saveCardButton")
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

private struct CardListView: View {
    let deck: Deck
    var onAdd: (String, String) -> Void
    var onDelete: (Flashcard) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var editingCard: Flashcard?
    @State private var addingCard = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(deck.sortedCards) { card in
                        Button { editingCard = card } label: {
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: card.isKnown ? "checkmark.circle.fill" : "circle.dashed")
                                    .foregroundStyle(card.isKnown ? .green : .orange)
                                    .accessibilityLabel(card.isKnown ? "Mastered" : "Still learning")
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(card.front).font(.headline).foregroundStyle(.primary)
                                    Text(card.back).font(.subheadline).foregroundStyle(.secondary)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .contentShape(Rectangle())
                        .accessibilityIdentifier("cardRow")
                    }
                    .onDelete { offsets in
                        offsets.map { deck.sortedCards[$0] }.forEach(onDelete)
                    }
                } footer: {
                    Text("Tap a card to edit it. Swipe left to delete.")
                }
            }
            .navigationTitle("\(deck.cards.count) cards")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.accessibilityIdentifier("cardListDoneButton")
                }
                ToolbarItem(placement: .primaryAction) {
                    Button { addingCard = true } label: { Image(systemName: "plus") }
                        .accessibilityLabel("Add a card")
                }
            }
            .sheet(item: $editingCard) { card in
                CardEditorView(title: "Edit card", front: card.front, back: card.back) { front, back in
                    card.front = front
                    card.back = back
                }
            }
            .sheet(isPresented: $addingCard) {
                CardEditorView(title: "New card", front: "", back: "", onSave: onAdd)
            }
        }
    }
}

/// Keeps the iOS 26 full-screen back swipe from leaving the session when a student swipes a card.
private struct BackSwipeBlocker: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> Controller { Controller() }
    func updateUIViewController(_ controller: Controller, context: Context) {}

    final class Controller: UIViewController {
        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            setContentPopEnabled(false)
        }

        override func viewWillDisappear(_ animated: Bool) {
            super.viewWillDisappear(animated)
            setContentPopEnabled(true)
        }

        private func setContentPopEnabled(_ enabled: Bool) {
            if #available(iOS 26.0, *) {
                navigationController?.interactiveContentPopGestureRecognizer?.isEnabled = enabled
            }
        }
    }
}
