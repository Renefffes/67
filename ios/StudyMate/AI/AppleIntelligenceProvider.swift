#if canImport(FoundationModels)
import Foundation
import FoundationModels

@available(iOS 26.0, *)
@Generable
struct AIStudySet {
    @Guide(description: "Flashcards covering the most important facts in the notes", .count(4...12))
    var flashcards: [AIFlashcard]

    @Guide(description: "Multiple-choice questions testing the notes", .count(3...8))
    var quiz: [AIQuizQuestion]
}

@available(iOS 26.0, *)
@Generable
struct AIFlashcard {
    @Guide(description: "A short question or key term")
    var front: String

    @Guide(description: "A concise answer or definition")
    var back: String
}

@available(iOS 26.0, *)
@Generable
struct AIQuizQuestion {
    var question: String

    @Guide(description: "Exactly four answer options", .count(4))
    var options: [String]

    @Guide(description: "Index of the correct option, from 0 to 3", .range(0...3))
    var answerIndex: Int

    @Guide(description: "One sentence explaining the correct answer")
    var explanation: String
}

@available(iOS 26.0, *)
struct AppleIntelligenceProvider: StudyAIProvider {
    /// The on-device model has a small context window, so long notes are trimmed.
    static let maxNotesLength = 6_000

    static var isAvailable: Bool { SystemLanguageModel.default.isAvailable }

    static var statusDescription: String {
        switch SystemLanguageModel.default.availability {
        case .available:
            return "Ready"
        case .unavailable(let reason):
            switch reason {
            case .deviceNotEligible: return "This device doesn't support Apple Intelligence"
            case .appleIntelligenceNotEnabled: return "Turn on Apple Intelligence in Settings"
            case .modelNotReady: return "Model is still downloading"
            @unknown default: return "Unavailable"
            }
        }
    }

    static func ping() async throws {
        _ = try await LanguageModelSession().respond(to: "Reply with OK.", options: GenerationOptions(maximumResponseTokens: 4))
    }

    func makeStudySet(from notes: String, title: String) async throws -> GeneratedStudySet {
        let session = LanguageModelSession(instructions: StudyAI.studySetInstructions)
        let prompt = "Title: \(title)\n\nNotes:\n\(String(notes.prefix(Self.maxNotesLength)))"
        let result = try await session.respond(to: prompt, generating: AIStudySet.self).content
        return GeneratedStudySet(
            flashcards: result.flashcards.map { GeneratedCard(front: $0.front, back: $0.back) },
            quiz: result.quiz.map {
                GeneratedQuestion(question: $0.question, options: $0.options, answerIndex: $0.answerIndex, explanation: $0.explanation)
            }
        )
    }

    func tutorReply(notes: String, title: String, history: [TutorTurn], question: String) async throws -> String {
        let session = LanguageModelSession(
            instructions: StudyAI.tutorInstructions(title: title, notes: String(notes.prefix(Self.maxNotesLength / 2)))
        )
        let recent = history.suffix(6)
            .map { ($0.isUser ? "Student: " : "Tutor: ") + $0.text }
            .joined(separator: "\n")
        let prompt = recent.isEmpty ? question : "Conversation so far:\n\(recent)\n\nStudent: \(question)"
        return try await session.respond(to: prompt).content
    }
}
#endif
