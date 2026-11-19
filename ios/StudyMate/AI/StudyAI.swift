import Foundation
import Observation

struct GeneratedCard: Codable, Equatable {
    var front: String
    var back: String
}

struct GeneratedQuestion: Codable, Equatable {
    var question: String
    var options: [String]
    var answerIndex: Int
    var explanation: String?
}

struct GeneratedStudySet: Codable, Equatable {
    var flashcards: [GeneratedCard]
    var quiz: [GeneratedQuestion]
}

struct TutorTurn: Equatable {
    let isUser: Bool
    let text: String
}

protocol StudyAIProvider {
    func makeStudySet(from notes: String, title: String) async throws -> GeneratedStudySet
    func tutorReply(notes: String, title: String, history: [TutorTurn], question: String) async throws -> String
}

enum StudyAIError: LocalizedError {
    case missingAPIKey
    case unavailable
    case badResponse(String)
    case emptyResult

    var errorDescription: String? {
        switch self {
        case .missingAPIKey: "No Gemini API key is set"
        case .unavailable: "Apple Intelligence isn't available on this device"
        case .badResponse(let detail): "The AI returned an unexpected response (\(detail))"
        case .emptyResult: "The AI didn't return any flashcards"
        }
    }
}

enum AIEngine: String, CaseIterable, Identifiable {
    case automatic
    case appleIntelligence
    case gemini
    case offline

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .automatic: "Automatic"
        case .appleIntelligence: "Apple Intelligence"
        case .gemini: "Google Gemini"
        case .offline: "Offline mode"
        }
    }
}

enum StudyAI {
    static let engineKey = "aiEngine"
    static let geminiModelKey = "geminiModel"
    static let defaultGeminiModel = "gemini-2.5-flash"

    struct Outcome {
        let set: GeneratedStudySet
        let engine: AIEngine
        let note: String?
    }

    static var selectedEngine: AIEngine {
        if AppEnvironment.isUITesting { return .offline }
        return AIEngine(rawValue: UserDefaults.standard.string(forKey: engineKey) ?? "") ?? .automatic
    }

    static var geminiModel: String {
        let stored = UserDefaults.standard.string(forKey: geminiModelKey)?.trimmingCharacters(in: .whitespaces) ?? ""
        return stored.isEmpty ? defaultGeminiModel : stored
    }

    /// Set when Automatic mode's Apple Intelligence attempt fails, so later requests go straight to the next engine.
    static var appleIntelligenceFailed: Bool {
        get { AIHealth.shared.appleIntelligenceFailed }
        set { AIHealth.shared.appleIntelligenceFailed = newValue }
    }

    /// Simulators and some devices report the on-device model as available but can't run it, so try a tiny request once.
    static func checkAppleIntelligence() async {
        guard !AppEnvironment.isUITesting, !AIHealth.shared.checked, appleIntelligenceAvailable,
              [.automatic, .appleIntelligence].contains(storedEngine) else { return }
        AIHealth.shared.checked = true
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            do { try await AppleIntelligenceProvider.ping() } catch { appleIntelligenceFailed = true }
        }
        #endif
    }

    static var hasGeminiKey: Bool { !(Keychain.geminiAPIKey ?? "").isEmpty }

    static func resolvedEngine(_ engine: AIEngine = selectedEngine) -> AIEngine {
        guard engine == .automatic else { return engine }
        if appleIntelligenceAvailable && !appleIntelligenceFailed { return .appleIntelligence }
        if hasGeminiKey { return .gemini }
        return .offline
    }

    static var appleIntelligenceAvailable: Bool {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            return AppleIntelligenceProvider.isAvailable
        }
        #endif
        return false
    }

    static var appleIntelligenceStatus: String {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            return AppleIntelligenceProvider.statusDescription
        }
        #endif
        return "Requires iOS 26"
    }

    static func provider(for engine: AIEngine) -> StudyAIProvider {
        switch engine {
        case .gemini:
            return GeminiProvider(apiKey: Keychain.geminiAPIKey ?? "", model: geminiModel)
        case .appleIntelligence:
            #if canImport(FoundationModels)
            if #available(iOS 26.0, *), AppleIntelligenceProvider.isAvailable {
                return AppleIntelligenceProvider()
            }
            #endif
            return UnavailableProvider()
        case .automatic, .offline:
            return OfflineProvider()
        }
    }

    static func makeStudySet(notes: String, title: String) async -> Outcome {
        let engine = resolvedEngine()
        let offline = { (note: String?) in
            Outcome(set: OfflineProvider.studySet(from: notes, title: title), engine: .offline, note: note)
        }
        guard engine != .offline else { return offline(nil) }
        do {
            let set = sanitize(try await provider(for: engine).makeStudySet(from: notes, title: title))
            guard !set.flashcards.isEmpty else { throw StudyAIError.emptyResult }
            return Outcome(set: set, engine: engine, note: nil)
        } catch {
            if selectedEngine == .automatic {
                guard engine == .appleIntelligence else { return offline(nil) }
                appleIntelligenceFailed = true
                return resolvedEngine() == .gemini ? await makeStudySet(notes: notes, title: title) : offline(nil)
            }
            return offline("\(engine.displayName) didn't work (\(error.localizedDescription)), so these were made in offline mode.")
        }
    }

    static func tutorReply(notes: String, title: String, history: [TutorTurn], question: String) async -> String {
        let engine = resolvedEngine()
        if engine != .offline {
            do {
                let reply = try await provider(for: engine)
                    .tutorReply(notes: notes, title: title, history: history, question: question)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !reply.isEmpty { return reply }
            } catch {
                let fallback = OfflineProvider.reply(notes: notes, title: title, history: history, question: question)
                if selectedEngine == .automatic { return fallback }
                return "\(fallback)\n\n(\(engine.displayName) didn't respond: \(error.localizedDescription).)"
            }
        }
        return OfflineProvider.reply(notes: notes, title: title, history: history, question: question)
    }

    static func sanitize(_ set: GeneratedStudySet) -> GeneratedStudySet {
        let cards = set.flashcards
            .map { GeneratedCard(front: $0.front.trimmed, back: $0.back.trimmed) }
            .filter { !$0.front.isEmpty && !$0.back.isEmpty }
        let quiz: [GeneratedQuestion] = set.quiz.compactMap { question in
            var options: [String] = []
            for option in question.options.map(\.trimmed) where !option.isEmpty && !options.contains(option) {
                options.append(option)
            }
            guard !question.question.trimmed.isEmpty, options.count >= 2 else { return nil }
            let original = question.options.indices.contains(question.answerIndex) ? question.options[question.answerIndex].trimmed : ""
            guard let answer = options.firstIndex(of: original) else { return nil }
            return GeneratedQuestion(question: question.question.trimmed, options: options, answerIndex: answer, explanation: question.explanation?.trimmed)
        }
        return GeneratedStudySet(flashcards: cards, quiz: quiz)
    }

    static let studySetInstructions = """
    You are a study assistant for students. From the student's notes, write flashcards and a multiple-choice quiz.
    Flashcards: short question or term on the front, a concise answer on the back. Cover the most important facts.
    Quiz: each question has exactly four options, one correct answer, and a one-sentence explanation.
    Use only information from the notes, in the same language as the notes.
    """

    static func tutorInstructions(title: String, notes: String) -> String {
        """
        You are a friendly, encouraging tutor helping a student study "\(title)".
        Answer clearly and briefly, using simple language and examples. Base answers on the student's notes below; \
        if something is not in the notes, say so and then explain it from general knowledge. \
        When asked to quiz the student, ask one question at a time.

        Student's notes:
        \(notes)
        """
    }
}

struct UnavailableProvider: StudyAIProvider {
    func makeStudySet(from notes: String, title: String) async throws -> GeneratedStudySet {
        throw StudyAIError.unavailable
    }

    func tutorReply(notes: String, title: String, history: [TutorTurn], question: String) async throws -> String {
        throw StudyAIError.unavailable
    }
}

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}

/// What this launch has learned about the on-device model; observable so engine labels update.
@Observable
final class AIHealth {
    nonisolated(unsafe) static let shared = AIHealth()
    var appleIntelligenceFailed = false
    var checked = false
}
