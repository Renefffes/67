import Foundation
import NaturalLanguage

/// Rule-based study helper that works without any AI model or network connection.
struct OfflineProvider: StudyAIProvider {
    static let maxCards = 12
    static let maxQuestions = 8

    func makeStudySet(from notes: String, title: String) async throws -> GeneratedStudySet {
        Self.studySet(from: notes, title: title)
    }

    func tutorReply(notes: String, title: String, history: [TutorTurn], question: String) async throws -> String {
        Self.reply(notes: notes, history: history, question: question)
    }

    // MARK: Flashcards and quiz

    static func studySet(from notes: String, title: String) -> GeneratedStudySet {
        var cards: [GeneratedCard] = []
        var definitionCards: Set<Int> = []
        var clozeCards: Set<Int> = []
        var sources: [String] = []
        for sentence in sentences(in: notes) where cards.count < maxCards {
            if let (term, definition, verb) = definition(in: sentence) {
                let front = verb.map { "What \($0) \(term.lowercasingLeadingArticle)?" } ?? term
                guard !cards.contains(where: { $0.front.lowercased() == front.lowercased() }) else { continue }
                definitionCards.insert(cards.count)
                cards.append(GeneratedCard(front: front, back: definition.capitalizedFirst))
                sources.append(sentence)
            } else if let keyword = keyword(in: sentence) {
                let blanked = sentence.replacingOccurrences(of: keyword, with: "_____", options: [], range: sentence.range(of: keyword))
                clozeCards.insert(cards.count)
                cards.append(GeneratedCard(front: blanked, back: keyword))
                sources.append(sentence)
            }
        }
        if cards.isEmpty {
            let summary = notes.trimmed
            let name = title.trimmed.isEmpty ? "these notes" : title.trimmed
            cards = [GeneratedCard(front: "Summarize \(name)", back: summary.isEmpty ? "(empty notes)" : String(summary.prefix(300)))]
        }

        let fallbackPool = keywords(in: notes, limit: 20)
        var quiz: [GeneratedQuestion] = []
        for (index, card) in cards.prefix(maxQuestions).enumerated() {
            let isCloze = clozeCards.contains(index)
            guard isCloze || definitionCards.contains(index) else { continue }
            let others = cards.enumerated()
                .filter { $0.offset != index && clozeCards.contains($0.offset) == isCloze && (isCloze || definitionCards.contains($0.offset)) }
                .map(\.element.back)
            var distractors: [String] = []
            for candidate in others + fallbackPool where distractors.count < 3 {
                let lower = candidate.lowercased()
                if lower != card.back.lowercased() && !distractors.contains(where: { $0.lowercased() == lower }) {
                    distractors.append(candidate)
                }
            }
            guard !distractors.isEmpty else { continue }
            var options = distractors
            let answerIndex = stableHash(card.front) % (options.count + 1)
            options.insert(card.back, at: answerIndex)
            let question = isCloze ? "Fill in the blank: \(card.front)" : card.front
            quiz.append(GeneratedQuestion(
                question: question,
                options: options,
                answerIndex: answerIndex,
                explanation: index < sources.count ? "From your notes: “\(sources[index]).”" : nil
            ))
        }
        return GeneratedStudySet(flashcards: cards, quiz: quiz)
    }

    static func sentences(in text: String) -> [String] {
        var result: [String] = []
        for rawLine in text.components(separatedBy: .newlines) {
            let line = stripBullet(rawLine.trimmed)
            guard !line.isEmpty else { continue }
            let tokenizer = NLTokenizer(unit: .sentence)
            tokenizer.string = line
            tokenizer.enumerateTokens(in: line.startIndex..<line.endIndex) { range, _ in
                var sentence = String(line[range]).trimmed
                while let last = sentence.last, ".!?;".contains(last) { sentence.removeLast() }
                if sentence.split(separator: " ").count >= 2 { result.append(sentence) }
                return true
            }
        }
        return result
    }

    static func definition(in sentence: String) -> (term: String, definition: String, verb: String?)? {
        let patterns: [(String, Bool)] = [
            (#"^(.{2,60}?)\s+(is|are|was|were|means|refers to)\s+(.{3,})$"#, true),
            (#"^([^:]{2,60}):\s*(.{3,})$"#, false),
            (#"^(.{2,60}?)\s+[-–—]\s+(.{3,})$"#, false),
        ]
        for (pattern, hasVerb) in patterns {
            guard
                let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
                let match = regex.firstMatch(in: sentence, range: NSRange(sentence.startIndex..., in: sentence))
            else { continue }
            let group = { (i: Int) in Range(match.range(at: i), in: sentence).map { String(sentence[$0]).trimmed } ?? "" }
            let term = group(1)
            guard term.split(separator: " ").count <= 6 else { continue }
            if hasVerb {
                let verb = group(2).lowercased()
                let question = ["are", "were"].contains(verb) ? verb : (verb == "was" ? "was" : "is")
                let definition = ["means", "refers to"].contains(verb) ? "\(verb.capitalizedFirst) \(group(3))" : group(3)
                return (term, definition, question)
            }
            return (term, group(2), nil)
        }
        return nil
    }

    static func keyword(in sentence: String) -> String? {
        let words = words(in: sentence).filter { $0.count >= 4 && !stopWords.contains($0.lowercased()) }
        guard sentence.split(separator: " ").count >= 4 else { return nil }
        return words.max { score($0) < score($1) }
    }

    static func keywords(in text: String, limit: Int) -> [String] {
        var seen: Set<String> = []
        var result: [String] = []
        let candidates = words(in: text)
            .filter { $0.count >= 4 && !stopWords.contains($0.lowercased()) }
            .sorted { score($0) > score($1) }
        for word in candidates where !seen.contains(word.lowercased()) {
            seen.insert(word.lowercased())
            result.append(word)
            if result.count == limit { break }
        }
        return result
    }

    private static func score(_ word: String) -> Int {
        word.count + (word.first?.isUppercase == true ? 3 : 0) + (word.contains(where: \.isNumber) ? 4 : 0)
    }

    private static func words(in text: String) -> [String] {
        text.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
    }

    private static func stripBullet(_ line: String) -> String {
        line.replacingOccurrences(of: #"^([•*·]\s*|[-–]\s+|\d+[.)]\s+)"#, with: "", options: .regularExpression)
    }

    static func stableHash(_ text: String) -> Int {
        text.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0x7fff_ffff }
    }

    // MARK: Tutor

    static let quizPrefix = "Quick question:"

    static func reply(notes: String, history: [TutorTurn], question: String) -> String {
        let lower = question.lowercased()
        let all = sentences(in: notes)
        let set = studySet(from: notes, title: "")

        if lower.contains("quiz") || lower.contains("test me") {
            let asked = history.filter { !$0.isUser && $0.text.hasPrefix(quizPrefix) }.count
            let card = set.flashcards[asked % set.flashcards.count]
            return "\(quizPrefix) \(card.front)\n\nType your answer and I'll check it."
        }

        if let last = history.last, !last.isUser, last.text.hasPrefix(quizPrefix),
           let card = set.flashcards.first(where: { last.text.hasPrefix("\(quizPrefix) \($0.front)\n") }) {
            let expected = Set(words(in: card.back.lowercased()).filter { !stopWords.contains($0) })
            let given = Set(words(in: lower))
            let correct = expected.isEmpty
                ? lower.contains(card.back.lowercased())
                : Double(expected.intersection(given).count) / Double(expected.count) >= 0.5
            return (correct ? "Nice, that's right!" : "Not quite.") + " The answer is: \(card.back).\n\nSay \"quiz me\" for another one."
        }

        let queryWords = Set(words(in: lower).filter { $0.count >= 3 && !stopWords.contains($0) })
        let ranked = all
            .map { sentence -> (String, Int) in
                let overlap = Set(words(in: sentence.lowercased())).intersection(queryWords).count
                return (sentence, overlap)
            }
            .filter { $0.1 > 0 }
            .sorted { $0.1 > $1.1 }
            .prefix(3)
            .map(\.0)

        if !ranked.isEmpty {
            return "Here's what your notes say:\n" + ranked.map { "• \($0)." }.joined(separator: "\n")
        }
        if lower.contains("summar") || lower.contains("explain") || lower.contains("main") || lower.contains("focus") {
            let key = all.prefix(4).map { "• \($0)." }.joined(separator: "\n")
            return key.isEmpty ? "Your notes are empty — add some notes first." : "The main ideas in your notes:\n\(key)"
        }
        let topics = keywords(in: notes, limit: 4).joined(separator: ", ")
        return "I couldn't find that in your notes. Try asking about \(topics.isEmpty ? "a topic from your notes" : topics).\n\nTip: turn on Apple Intelligence or add a Gemini key in Settings for a smarter tutor."
    }

    static let stopWords: Set<String> = [
        "the", "and", "for", "are", "but", "not", "you", "all", "any", "can", "had", "her", "was", "one", "our", "out",
        "has", "have", "this", "that", "with", "from", "they", "will", "would", "there", "their", "what", "about",
        "which", "when", "make", "like", "into", "than", "them", "then", "these", "those", "some", "such", "only",
        "also", "very", "more", "most", "other", "each", "been", "being", "were", "does", "doing", "your", "where",
        "while", "because", "through", "between", "after", "before", "over", "under", "again", "once", "here",
        "why", "how", "who", "its", "it's", "is", "of", "to", "in", "a", "an", "on", "as", "by", "or", "it", "be",
        "me", "tell", "explain", "please", "used", "uses", "using",
    ]
}

extension String {
    var capitalizedFirst: String {
        guard let first else { return self }
        return first.uppercased() + dropFirst()
    }
}

private extension String {
    var lowercasingLeadingArticle: String {
        for article in ["The ", "A ", "An "] where hasPrefix(article) {
            return article.lowercased() + dropFirst(article.count)
        }
        return self
    }
}
