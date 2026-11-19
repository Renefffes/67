import SwiftData
import SwiftUI

struct QuizView: View {
    let deck: Deck
    @State private var questions: [QuizQuestion] = []
    @State private var index = 0
    @State private var selected: Int?
    @State private var score = 0
    @State private var finished = false

    var body: some View {
        Group {
            if questions.isEmpty {
                ContentUnavailableView(
                    "No quiz questions",
                    systemImage: "questionmark.square.dashed",
                    description: Text("Add more notes and regenerate the deck to get a quiz.")
                )
            } else if finished {
                results
            } else {
                ScrollView { questionView.padding() }
            }
        }
        .navigationTitle("Quiz")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { if questions.isEmpty { questions = deck.sortedQuestions } }
    }

    private var questionView: some View {
        let question = questions[index]
        return VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Question \(index + 1) of \(questions.count)")
                Spacer()
                Text("Score: \(score)")
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)

            Text(question.prompt)
                .font(.title3.weight(.semibold))
                .accessibilityIdentifier("quizQuestion")

            ForEach(Array(question.options.enumerated()), id: \.offset) { offset, option in
                Button { select(offset, for: question) } label: {
                    HStack {
                        Text(option).multilineTextAlignment(.leading)
                        Spacer()
                        if let selected {
                            if offset == question.answerIndex {
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                            } else if offset == selected {
                                Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
                            }
                        }
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(background(for: offset, question: question), in: RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)
                .disabled(selected != nil)
                .accessibilityIdentifier("quizOption_\(offset)")
            }

            if let selected {
                let correct = selected == question.answerIndex
                VStack(alignment: .leading, spacing: 6) {
                    Text(correct ? "Correct!" : "Not quite — the answer is “\(question.correctAnswer)”.")
                        .font(.headline)
                        .foregroundStyle(correct ? .green : .red)
                        .accessibilityIdentifier("quizFeedback")
                    if !question.explanation.isEmpty {
                        Text(question.explanation).font(.callout).foregroundStyle(.secondary)
                    }
                }
                Button(index + 1 < questions.count ? "Next question" : "See results") { next() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .frame(maxWidth: .infinity)
                    .accessibilityIdentifier("quizNextButton")
            }
        }
    }

    private var results: some View {
        VStack(spacing: 16) {
            Image(systemName: score * 2 >= questions.count ? "trophy.fill" : "book.fill")
                .font(.system(size: 64))
                .foregroundStyle(.yellow)
            Text("\(score) / \(questions.count)")
                .font(.system(size: 48, weight: .bold, design: .rounded))
                .accessibilityIdentifier("quizScore")
            Text(score == questions.count ? "Perfect score!" : score * 2 >= questions.count ? "Nice work — keep it up!" : "Review your flashcards and try again.")
                .foregroundStyle(.secondary)
            Button("Try again") {
                index = 0
                score = 0
                selected = nil
                finished = false
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("quizRetryButton")
        }
        .padding()
    }

    private func background(for offset: Int, question: QuizQuestion) -> Color {
        guard let selected else { return Color(.secondarySystemBackground) }
        if offset == question.answerIndex { return .green.opacity(0.18) }
        if offset == selected { return .red.opacity(0.18) }
        return Color(.secondarySystemBackground)
    }

    private func select(_ offset: Int, for question: QuizQuestion) {
        selected = offset
        if offset == question.answerIndex { score += 1 }
    }

    private func next() {
        selected = nil
        if index + 1 < questions.count {
            index += 1
        } else {
            finished = true
            guard deck.sortedQuestions.map(\.persistentModelID) == questions.map(\.persistentModelID) else { return }
            deck.lastQuizScore = score
            deck.lastQuizTotal = questions.count
        }
    }
}
