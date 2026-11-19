import SwiftData
import SwiftUI

struct QuizItem: Identifiable, Equatable {
    let id: Int
    let prompt: String
    let options: [String]
    let answerIndex: Int
    let explanation: String

    var correctAnswer: String { options[answerIndex] }

    static func items(from questions: [QuizQuestion]) -> [QuizItem] {
        questions.enumerated().compactMap { offset, question in
            guard question.options.indices.contains(question.answerIndex) else { return nil }
            return QuizItem(
                id: offset,
                prompt: question.prompt,
                options: question.options,
                answerIndex: question.answerIndex,
                explanation: question.explanation
            )
        }
    }

    /// Shuffles question order and option order, so a retake can't be passed by remembering positions.
    static func shuffled(_ items: [QuizItem], using generator: inout some RandomNumberGenerator) -> [QuizItem] {
        items.shuffled(using: &generator).map { item in
            let order = item.options.indices.shuffled(using: &generator)
            return QuizItem(
                id: item.id,
                prompt: item.prompt,
                options: order.map { item.options[$0] },
                answerIndex: order.firstIndex(of: item.answerIndex) ?? 0,
                explanation: item.explanation
            )
        }
    }
}

/// SplitMix64, seeded so UI tests see the same order every run.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

struct QuizView: View {
    let deck: Deck
    @State private var round: [QuizItem] = []
    @State private var isFullQuiz = true
    @State private var index = 0
    @State private var selected: Int?
    @State private var answers: [Int: Int] = [:]
    @State private var finished = false
    @State private var roundSourceIDs: [PersistentIdentifier] = []
    @State private var generator = SeededGenerator(seed: AppEnvironment.isUITesting ? 42 : .random(in: 0...UInt64.max))

    private var score: Int { round.filter { answers[$0.id] == $0.answerIndex }.count }
    private var missed: [QuizItem] { round.filter { answers[$0.id] != $0.answerIndex } }

    var body: some View {
        Group {
            if round.isEmpty {
                ContentUnavailableView(
                    "No quiz questions",
                    systemImage: "questionmark.square.dashed",
                    description: Text("Add more notes and regenerate the deck to get a quiz.")
                )
            } else if finished {
                results
            } else {
                ScrollView { questionView.padding() }
                    .safeAreaInset(edge: .bottom) { feedbackBar }
            }
        }
        .navigationTitle(isFullQuiz ? "Quiz" : "Missed questions")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { if round.isEmpty { start(with: QuizItem.items(from: deck.sortedQuestions), full: true) } }
        .sensoryFeedback(trigger: selected) { _, new in
            guard let new, round.indices.contains(index) else { return nil }
            return new == round[index].answerIndex ? .success : .error
        }
    }

    private var questionView: some View {
        let question = round[index]
        return VStack(alignment: .leading, spacing: 16) {
            VStack(spacing: 6) {
                HStack {
                    Text("Question \(index + 1) of \(round.count)")
                        .accessibilityIdentifier("quizProgress")
                    Spacer()
                    Text("Score: \(score)")
                        .accessibilityIdentifier("quizRunningScore")
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
                ProgressView(value: Double(index + (selected == nil ? 0 : 1)), total: Double(round.count))
            }

            Text(question.prompt)
                .font(.title3.weight(.semibold))
                .accessibilityIdentifier("quizQuestion")

            ForEach(Array(question.options.enumerated()), id: \.offset) { offset, option in
                Button { select(offset) } label: {
                    HStack {
                        Text(option).multilineTextAlignment(.leading)
                        Spacer()
                        if let icon = icon(for: offset, question: question) {
                            Image(systemName: icon.name).foregroundStyle(icon.color)
                        }
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(background(for: offset, question: question), in: RoundedRectangle(cornerRadius: 14))
                    .overlay {
                        if selected == offset {
                            RoundedRectangle(cornerRadius: 14).strokeBorder(.primary.opacity(0.35), lineWidth: 1.5)
                        }
                    }
                    .contentShape(RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)
                .allowsHitTesting(selected == nil)
                .accessibilityIdentifier("quizOption_\(offset)")
                .accessibilityValue(accessibilityValue(for: offset, question: question))
            }
        }
    }

    @ViewBuilder
    private var feedbackBar: some View {
        if let selected {
            let question = round[index]
            let correct = selected == question.answerIndex
            VStack(alignment: .leading, spacing: 10) {
                Label(
                    correct ? "Correct!" : "Not quite — the answer is “\(question.correctAnswer)”.",
                    systemImage: correct ? "checkmark.circle.fill" : "xmark.circle.fill"
                )
                .font(.headline)
                .foregroundStyle(correct ? .green : .red)
                .accessibilityIdentifier("quizFeedback")
                if !question.explanation.isEmpty {
                    Text(question.explanation).font(.callout).foregroundStyle(.secondary)
                }
                Button { next() } label: {
                    Text(index + 1 < round.count ? "Next question" : "See results").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .accessibilityIdentifier("quizNextButton")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(.bar)
        }
    }

    private var results: some View {
        let missed = missed
        let total = round.count
        return ScrollView {
            VStack(spacing: 16) {
                Image(systemName: score == total ? "trophy.fill" : score * 2 >= total ? "star.fill" : "book.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(score * 2 >= total ? .yellow : .indigo)
                Text("\(score) / \(total)")
                    .font(.system(size: 48, weight: .bold, design: .rounded))
                    .accessibilityIdentifier("quizScore")
                Text(score == total ? "Perfect score!" : score * 2 >= total ? "Nice work — keep it up!" : "Review the answers below and try again.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                VStack(spacing: 10) {
                    if !missed.isEmpty {
                        Button { start(with: missed, full: false) } label: {
                            Text(missed.count == 1 ? "Retry the question I missed" : "Retry the \(missed.count) I missed")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .accessibilityIdentifier("quizRetryMissedButton")
                    }
                    Button { start(with: QuizItem.items(from: deck.sortedQuestions), full: true) } label: {
                        Text(isFullQuiz ? "Retake the quiz" : "Retake the full quiz").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("quizRetryButton")
                }
                .controlSize(.large)

                if !missed.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Review what you missed").font(.headline)
                        ForEach(missed) { item in
                            missedRow(item)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 8)
                }
            }
            .padding()
        }
    }

    private func missedRow(_ item: QuizItem) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(item.prompt).font(.subheadline.weight(.semibold))
            if let chosen = answers[item.id], item.options.indices.contains(chosen) {
                Label("You said: \(item.options[chosen])", systemImage: "xmark.circle.fill")
                    .foregroundStyle(.red)
            }
            Label("Answer: \(item.correctAnswer)", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        }
        .font(.callout)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("quizMissedRow")
    }

    private func icon(for offset: Int, question: QuizItem) -> (name: String, color: Color)? {
        guard let selected else { return nil }
        if offset == question.answerIndex { return ("checkmark.circle.fill", .green) }
        if offset == selected { return ("xmark.circle.fill", .red) }
        return nil
    }

    private func background(for offset: Int, question: QuizItem) -> Color {
        guard let selected else { return Color(.secondarySystemBackground) }
        if offset == question.answerIndex { return .green.opacity(0.18) }
        if offset == selected { return .red.opacity(0.18) }
        return Color(.secondarySystemBackground).opacity(0.5)
    }

    private func accessibilityValue(for offset: Int, question: QuizItem) -> String {
        guard let selected else { return "" }
        if offset == question.answerIndex { return offset == selected ? "Your answer, correct" : "Correct answer" }
        return offset == selected ? "Your answer, incorrect" : ""
    }

    private func select(_ offset: Int) {
        guard selected == nil else { return }
        selected = offset
        answers[round[index].id] = offset
    }

    private func next() {
        selected = nil
        if index + 1 < round.count {
            index += 1
        } else {
            finished = true
            guard isFullQuiz, deck.sortedQuestions.map(\.persistentModelID) == roundSourceIDs else { return }
            deck.lastQuizScore = score
            deck.lastQuizTotal = round.count
        }
    }

    private func start(with items: [QuizItem], full: Bool) {
        roundSourceIDs = deck.sortedQuestions.map(\.persistentModelID)
        round = QuizItem.shuffled(items, using: &generator)
        isFullQuiz = full
        index = 0
        selected = nil
        answers = [:]
        finished = false
    }
}
