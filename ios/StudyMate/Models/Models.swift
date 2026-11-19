import Foundation
import SwiftData

@Model
final class Deck {
    var id: UUID
    var title: String
    var notes: String
    var createdAt: Date
    var engine: String
    var generationNote: String?
    var lastQuizScore: Int?
    var lastQuizTotal: Int?

    @Relationship(deleteRule: .cascade, inverse: \Flashcard.deck)
    var cards: [Flashcard] = []

    @Relationship(deleteRule: .cascade, inverse: \QuizQuestion.deck)
    var questions: [QuizQuestion] = []

    @Relationship(deleteRule: .cascade, inverse: \ChatMessage.deck)
    var messages: [ChatMessage] = []

    init(title: String, notes: String, engine: String, generationNote: String? = nil) {
        self.id = UUID()
        self.title = title
        self.notes = notes
        self.createdAt = .now
        self.engine = engine
        self.generationNote = generationNote
    }

    var sortedCards: [Flashcard] { cards.sorted { $0.order < $1.order } }
    var sortedQuestions: [QuizQuestion] { questions.sorted { $0.order < $1.order } }
    var sortedMessages: [ChatMessage] { messages.sorted { $0.order < $1.order } }
    var knownCount: Int { cards.filter(\.isKnown).count }

    func apply(_ set: GeneratedStudySet, engine: AIEngine, note: String?) {
        if let context = modelContext {
            cards.forEach(context.delete)
            questions.forEach(context.delete)
        }
        cards.removeAll()
        questions.removeAll()
        self.engine = engine.displayName
        self.generationNote = note
        lastQuizScore = nil
        lastQuizTotal = nil
        for (index, card) in set.flashcards.enumerated() {
            cards.append(Flashcard(front: card.front, back: card.back, order: index))
        }
        for (index, question) in set.quiz.enumerated() {
            questions.append(QuizQuestion(
                prompt: question.question,
                options: question.options,
                answerIndex: question.answerIndex,
                explanation: question.explanation ?? "",
                order: index
            ))
        }
    }
}

@Model
final class Flashcard {
    var front: String
    var back: String
    var order: Int
    var isKnown: Bool = false
    var deck: Deck?

    init(front: String, back: String, order: Int) {
        self.front = front
        self.back = back
        self.order = order
    }
}

@Model
final class QuizQuestion {
    var prompt: String
    var options: [String]
    var answerIndex: Int
    var explanation: String
    var order: Int
    var deck: Deck?

    init(prompt: String, options: [String], answerIndex: Int, explanation: String, order: Int) {
        self.prompt = prompt
        self.options = options
        self.answerIndex = answerIndex
        self.explanation = explanation
        self.order = order
    }

    var correctAnswer: String {
        options.indices.contains(answerIndex) ? options[answerIndex] : ""
    }
}

@Model
final class ChatMessage {
    var isUser: Bool
    var text: String
    var order: Int
    var createdAt: Date
    var deck: Deck?

    init(isUser: Bool, text: String, order: Int) {
        self.isUser = isUser
        self.text = text
        self.order = order
        self.createdAt = .now
    }
}
