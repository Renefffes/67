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
        Self.reply(notes: notes, title: title, history: history, question: question)
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

    static let quizPrefix = "Quick question: "
    static let quizHint = "Type your answer, or say “show answer”."
    static let smarterTutorTip = "Tip: add a free Gemini key in Settings for a tutor that can explain things beyond your notes."

    static func reply(notes: String, title: String = "", history: [TutorTurn], question: String) -> String {
        let lower = question.lowercased().trimmed
        let all = sentences(in: notes)
        guard !notes.trimmed.isEmpty else { return "Your notes are empty — add some notes first." }
        let cards = studySet(from: notes, title: title).flashcards
        let name = title.trimmed.isEmpty ? "your notes" : "“\(title.trimmed)”"
        let alreadySaid = history.filter { !$0.isUser }.map(\.text).joined(separator: "\n")

        if let pending = pendingQuizCard(history: history, cards: cards), !isQuestion(lower) && !isQuizCommand(lower) || isSkip(lower) {
            if isStop(lower) { return "Quiz paused. Ask me anything about \(name), or say “quiz me” to keep going." }
            if isSkip(lower) || isNext(lower) {
                return "The answer is: \(pending.back)\n\n" + quizQuestion(history: history, cards: cards)
            }
            return grade(answer: question, card: pending) + "\n\n" + quizQuestion(history: history, cards: cards)
        }

        if lower.contains("quiz") || lower.contains("test me") || (isNext(lower) && lastTutorTurnWasQuiz(history)) {
            return quizQuestion(history: history, cards: cards)
        }

        let index = SentenceIndex(sentences: all)
        var query = contentWords(lower)
        if index.rank(query).isEmpty, let smallTalk = smallTalkReply(lower, name: name, topics: topicList(notes)) {
            return smallTalk
        }
        let followUp = isFollowUp(lower)
        let previous = followUp ? previousTopic(history: history, index: index) : nil
        if let previous { query.formUnion(previous) }

        let ranked = index.rank(query)
        let unseen = ranked.filter { !alreadySaid.contains($0) }
        let topic = index.label(for: previous ?? query)

        if wantsMore(lower) {
            let related = index.rank(query, minShare: 0)
            let pool = related.isEmpty ? all : related
            let more = pool.filter { !alreadySaid.contains($0) }.prefix(3)
            if !more.isEmpty {
                return "Here's more from your notes\(topic.map { " about \($0)" } ?? ""):\n" + bullets(more)
            }
            return "That's everything your notes say\(topic.map { " about \($0)" } ?? ""). Try asking about \(topicList(notes)), or say “quiz me”."
                + tipIfNeeded(alreadySaid)
        }

        if !ranked.isEmpty {
            if followUp && unseen.isEmpty {
                return "Your notes don't go further than this\(topic.map { " on \($0)" } ?? ""):\n" + bullets(ranked.prefix(2))
                    + tipIfNeeded(alreadySaid)
            }
            return "Here's what your notes say:\n" + bullets((followUp && !unseen.isEmpty ? unseen : ranked).prefix(3))
        }
        if lower.contains("summar") || lower.contains("explain") || lower.contains("main") || lower.contains("focus") || lower.contains("overview") {
            return "The main ideas in \(name):\n" + bullets(all.prefix(4))
                + (all.count > 4 ? "\n\nSay “tell me more” for the rest." : "")
        }
        return "I couldn't find that in \(name). Try asking about \(topicList(notes))."
            + tipIfNeeded(alreadySaid)
    }

    private static func bullets<S: Sequence>(_ sentences: S) -> String where S.Element == String {
        sentences.map { "• \($0)." }.joined(separator: "\n")
    }

    private static func tipIfNeeded(_ alreadySaid: String) -> String {
        alreadySaid.contains(smarterTutorTip) ? "" : "\n\n" + smarterTutorTip
    }

    private static func topicList(_ notes: String) -> String {
        let topics = keywords(in: notes, limit: 4)
        guard let last = topics.last else { return "a topic from your notes" }
        return topics.count == 1 ? last : topics.dropLast().joined(separator: ", ") + " or " + last
    }

    // MARK: Tutor quiz

    private static func quizQuestion(history: [TutorTurn], cards: [GeneratedCard]) -> String {
        let asked = history.filter { !$0.isUser && $0.text.contains(quizPrefix) }.count
        let card = cards[asked % cards.count]
        return "\(quizPrefix)\(card.front)\n\n\(quizHint)"
    }

    private static func lastTutorTurnWasQuiz(_ history: [TutorTurn]) -> Bool {
        history.last(where: { !$0.isUser })?.text.contains(quizPrefix) == true
    }

    static func pendingQuizCard(history: [TutorTurn], cards: [GeneratedCard]) -> GeneratedCard? {
        guard let last = history.last, !last.isUser, let range = last.text.range(of: quizPrefix) else { return nil }
        let line = last.text[range.upperBound...].prefix { $0 != "\n" }
        let asked = history.filter { !$0.isUser && $0.text.contains(quizPrefix) }.count
        let askedCard = cards.isEmpty ? nil : cards[(asked - 1) % cards.count]
        if let askedCard, askedCard.front == line { return askedCard }
        return cards.first { $0.front == line }
    }

    static func grade(answer: String, card: GeneratedCard) -> String {
        let expected = answerWords(card.back)
        let given = answerWords(answer)
        let matched = expected.filter { word in given.contains { isWordForm($0, of: word) } }.count
        let correct = expected.isEmpty
            ? answer.lowercased().contains(card.back.lowercased())
            : matched * 2 >= expected.count
        if correct { return "Correct! The answer is: \(card.back)." }
        if matched > 0 { return "Partly right. The full answer is: \(card.back)." }
        return "Not quite. The answer is: \(card.back)."
    }

    /// Keeps short tokens such as chemical symbols ("Fe") and numbers, unlike `contentWords`.
    private static func answerWords(_ text: String) -> Set<String> {
        Set(words(in: text.lowercased()).filter { !stopWords.contains($0) }.map(normalized))
    }

    /// "divide" matches "divides" or "divided", but "titan" does not match "titanium".
    private static func isWordForm(_ a: String, of b: String) -> Bool {
        let (short, long) = a.count <= b.count ? (a, b) : (b, a)
        guard short.count >= 3 || short == long, long.hasPrefix(short) else { return false }
        let suffix = String(long.dropFirst(short.count))
        if suffix == "d" { return short.hasSuffix("e") }
        return ["", "s", "es", "ed", "ing", "ly"].contains(suffix)
    }

    // MARK: Tutor intents

    private static func isQuestion(_ text: String) -> Bool {
        let first = text.split(separator: " ").first.map(String.init) ?? ""
        return ["what", "what's", "why", "how", "when", "where", "who", "which", "can", "could", "explain", "tell", "summarize", "summarise", "describe"].contains(first)
            && (text.hasSuffix("?") || ["explain", "summarize", "summarise", "describe"].contains(first))
    }

    private static func isQuizCommand(_ text: String) -> Bool {
        ["quiz me", "test me"].contains { text.hasPrefix($0) }
    }

    private static func isSkip(_ text: String) -> Bool {
        ["show answer", "show the answer", "i don't know", "i dont know", "idk", "no idea", "skip", "give up", "tell me the answer"]
            .contains { phrase in
                let bare = text.trimmingCharacters(in: .punctuationCharacters)
                return bare == phrase || (phrase.contains(" ") && bare.hasPrefix(phrase))
            }
    }

    private static func isNext(_ text: String) -> Bool {
        ["next", "another", "next one", "another one", "one more", "again"].contains(text.trimmingCharacters(in: .punctuationCharacters))
    }

    private static func isStop(_ text: String) -> Bool {
        ["stop", "done", "enough", "quit", "end quiz", "stop quiz", "i'm done", "that's enough"].contains(text.trimmingCharacters(in: .punctuationCharacters))
    }

    private static func wantsMore(_ text: String) -> Bool {
        ["tell me more", "more about", "go on", "continue", "anything else", "what else", "more detail", "elaborate", "keep going"]
            .contains { text.contains($0) } || text.trimmingCharacters(in: .punctuationCharacters) == "more"
    }

    private static func isFollowUp(_ text: String) -> Bool {
        let words = text.components(separatedBy: CharacterSet.alphanumerics.union(["'"]).inverted).filter { !$0.isEmpty }
        let cues: Set<String> = ["it", "its", "it's", "that", "this", "they", "them", "those", "these", "he", "she", "more", "else"]
        let bareWhy = words.contains("why") && contentWords(text).isEmpty
        return words.count <= 8 && (words.contains { cues.contains($0) } || bareWhy) || wantsMore(text)
    }

    private static func smallTalkReply(_ text: String, name: String, topics: String) -> String? {
        let words = Set(text.components(separatedBy: CharacterSet.letters.union(["'"]).inverted).filter { !$0.isEmpty })
        guard words.count <= 4 else { return nil }
        if !words.isDisjoint(with: ["hi", "hello", "hey", "hiya", "yo", "morning"]) {
            return "Hi! Ready to study \(name)? Ask me about \(topics), or say “quiz me”."
        }
        if !words.isDisjoint(with: ["thanks", "thank", "thx", "ty", "cheers"]) {
            return "You're welcome! Want me to quiz you? Just say “quiz me”."
        }
        if !words.isDisjoint(with: ["ok", "okay", "cool", "nice", "great", "got", "k"]) {
            return "Great! Ask another question about \(name), or say “quiz me” to test yourself."
        }
        if !words.isDisjoint(with: ["bye", "goodbye", "cya"]) {
            return "Good luck with your studying!"
        }
        return nil
    }

    private static func previousTopic(history: [TutorTurn], index: SentenceIndex) -> Set<String>? {
        for turn in history.reversed() where turn.isUser {
            let words = contentWords(turn.text.lowercased())
            if !index.rank(words).isEmpty { return words }
        }
        return nil
    }

    /// Lowercased content words of `text`, with plural and verb "s" endings removed so "builds" matches "build".
    static func contentWords(_ text: String) -> Set<String> {
        Set(words(in: text).filter { $0.count >= 3 && !stopWords.contains($0) }.map(normalized))
    }

    static func normalized(_ word: String) -> String {
        guard word.count > 4, word.hasSuffix("s"), !word.hasSuffix("ss"), !word.hasSuffix("is"), !word.hasSuffix("us") else { return word }
        return String(word.dropLast())
    }

    /// Ranks note sentences by how many rare query words they contain, so a word that appears everywhere ("cell") counts for little.
    struct SentenceIndex {
        let sentences: [String]
        let words: [Set<String>]
        let weights: [String: Double]

        init(sentences: [String]) {
            self.sentences = sentences
            words = sentences.map { OfflineProvider.contentWords($0.lowercased()) }
            var frequency: [String: Int] = [:]
            for set in words { for word in set { frequency[word, default: 0] += 1 } }
            let count = Double(sentences.count)
            weights = frequency.mapValues { log((count + 1) / Double($0)) + 0.1 }
        }

        func rank(_ query: Set<String>, minShare: Double = 0.5) -> [String] {
            let scored = sentences.indices
                .map { (index: $0, score: words[$0].intersection(query).reduce(0) { $0 + (weights[$1] ?? 0) }) }
                .filter { $0.score > 0 }
            guard let best = scored.map(\.score).max() else { return [] }
            return scored
                .filter { $0.score >= best * minShare }
                .sorted { $0.score > $1.score || ($0.score == $1.score && $0.index < $1.index) }
                .map { sentences[$0.index] }
        }

        func label(for query: Set<String>) -> String? {
            query.filter { weights[$0] != nil }.max { (weights[$0] ?? 0) < (weights[$1] ?? 0) }
        }
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
