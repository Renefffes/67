import XCTest
@testable import StudyMate

final class OfflineProviderTests: XCTestCase {
    func testDefinitionsBecomeQuestionCards() {
        let set = OfflineProvider.studySet(from: "Osmosis is the movement of water across a membrane.", title: "Bio")
        XCTAssertEqual(set.flashcards.first, GeneratedCard(front: "What is Osmosis?", back: "The movement of water across a membrane"))
    }

    func testLeadingArticleIsLowercasedInQuestion() {
        let set = OfflineProvider.studySet(from: "The cell is the basic unit of life.", title: "")
        XCTAssertEqual(set.flashcards.first?.front, "What is the cell?")
    }

    func testColonNotesBecomeTermCards() {
        let set = OfflineProvider.studySet(from: "- Mitosis: cell division producing two identical cells", title: "")
        XCTAssertEqual(set.flashcards.first?.front, "Mitosis")
        XCTAssertEqual(set.flashcards.first?.back, "Cell division producing two identical cells")
    }

    func testOtherSentencesBecomeClozeCards() {
        let set = OfflineProvider.studySet(from: "The French Revolution started in 1789 in Paris.", title: "")
        let card = try? XCTUnwrap(set.flashcards.first)
        XCTAssertTrue(card?.front.contains("_____") == true)
        XCTAssertFalse(card?.back.isEmpty ?? true)
    }

    func testQuizQuestionsAreValid() {
        let set = OfflineProvider.studySet(from: SampleNotes.text, title: SampleNotes.title)
        XCTAssertGreaterThanOrEqual(set.flashcards.count, 6)
        XCTAssertFalse(set.quiz.isEmpty)
        for question in set.quiz {
            XCTAssertTrue(question.options.indices.contains(question.answerIndex))
            XCTAssertEqual(Set(question.options).count, question.options.count)
            XCTAssertGreaterThanOrEqual(question.options.count, 2)
        }
    }

    func testEmptyishNotesStillProduceACard() {
        let set = OfflineProvider.studySet(from: "Cells", title: "Bio")
        XCTAssertEqual(set.flashcards.count, 1)
    }

    func testTutorFindsRelevantSentence() {
        let reply = OfflineProvider.reply(notes: SampleNotes.text, history: [], question: "What do ribosomes do?")
        XCTAssertTrue(reply.contains("build proteins"), reply)
    }

    func testSanitizeDropsInvalidQuestions() {
        let raw = GeneratedStudySet(
            flashcards: [GeneratedCard(front: " Q ", back: " A "), GeneratedCard(front: "", back: "x")],
            quiz: [
                GeneratedQuestion(question: "Good?", options: ["a", "b", "b", "c"], answerIndex: 3, explanation: nil),
                GeneratedQuestion(question: "Bad index", options: ["a", "b"], answerIndex: 7, explanation: nil),
            ]
        )
        let clean = StudyAI.sanitize(raw)
        XCTAssertEqual(clean.flashcards, [GeneratedCard(front: "Q", back: "A")])
        XCTAssertEqual(clean.quiz.count, 1)
        XCTAssertEqual(clean.quiz[0].options, ["a", "b", "c"])
        XCTAssertEqual(clean.quiz[0].answerIndex, 2)
    }

    func testGeminiResponseParsing() throws {
        let json: [String: Any] = ["candidates": [["content": ["parts": [["text": "Hello"], ["text": " there"]]]]]]
        XCTAssertEqual(try GeminiProvider.text(from: json), "Hello there")
        XCTAssertThrowsError(try GeminiProvider.text(from: ["candidates": []]))
    }
    private func turns(_ pairs: [(Bool, String)]) -> [TutorTurn] { pairs.map { TutorTurn(isUser: $0.0, text: $0.1) } }

    func testTutorQuizHidesAnswerUntilStudentReplies() {
        let question = OfflineProvider.reply(notes: SampleNotes.text, history: [], question: "Quiz me on this")
        XCTAssertTrue(question.hasPrefix("Quick question: What is the cell?"), question)
        XCTAssertFalse(question.contains("basic unit of life"), question)

        let history = turns([(true, "Quiz me on this"), (false, question)])
        let graded = OfflineProvider.reply(notes: SampleNotes.text, history: history, question: "the basic unit of life")
        XCTAssertTrue(graded.hasPrefix("Correct!"), graded)
        XCTAssertTrue(graded.contains("Quick question: What is the nucleus?"), graded)

        let wrong = OfflineProvider.reply(notes: SampleNotes.text, history: history, question: "a type of sugar")
        XCTAssertTrue(wrong.hasPrefix("Not quite. The answer is: The basic unit of life"), wrong)

        let revealed = OfflineProvider.reply(notes: SampleNotes.text, history: history, question: "I don't know")
        XCTAssertTrue(revealed.hasPrefix("The answer is: The basic unit of life"), revealed)
    }

    func testTutorGradesAnswerWithDifferentWordForms() {
        let card = GeneratedCard(front: "What are ribosomes?", back: "Tiny structures that build proteins")
        XCTAssertTrue(OfflineProvider.grade(answer: "they builds proteins", card: card).hasPrefix("Correct!"))
        XCTAssertTrue(OfflineProvider.grade(answer: "proteins", card: card).hasPrefix("Partly right"))
    }

    func testTutorFollowUpUsesPreviousTopic() {
        let first = OfflineProvider.reply(notes: SampleNotes.text, history: [], question: "What does the nucleus do?")
        XCTAssertTrue(first.contains("stores DNA"), first)
        let history = turns([(true, "What does the nucleus do?"), (false, first)])
        let why = OfflineProvider.reply(notes: SampleNotes.text, history: history, question: "Why is that important?")
        XCTAssertTrue(why.contains("nucleus"), why)
        XCTAssertFalse(why.contains("couldn't find"), why)
        let more = OfflineProvider.reply(notes: SampleNotes.text, history: history, question: "Tell me more")
        XCTAssertTrue(more.contains("everything your notes say about nucleus"), more)
    }

    func testTutorTellMeMoreContinuesSummary() {
        let summary = OfflineProvider.reply(notes: SampleNotes.text, history: [], question: "Explain the main ideas simply")
        let more = OfflineProvider.reply(notes: SampleNotes.text, history: turns([(true, "Explain the main ideas simply"), (false, summary)]), question: "Tell me more")
        XCTAssertTrue(more.contains("Osmosis"), more)
        XCTAssertFalse(more.contains("basic unit of life"), more)
    }

    func testTutorRanksRareWordsAboveCommonOnes() {
        let reply = OfflineProvider.reply(notes: SampleNotes.text, history: [], question: "How do chloroplasts work in a cell?")
        XCTAssertTrue(reply.contains("chlorophyll"), reply)
        XCTAssertFalse(reply.contains("basic unit of life"), reply)
    }

    func testTutorRepeatsRelevantNotesForANewQuestion() {
        let summary = OfflineProvider.reply(notes: SampleNotes.text, history: [], question: "Explain the main ideas simply")
        let reply = OfflineProvider.reply(notes: SampleNotes.text, history: turns([(true, "Explain"), (false, summary)]), question: "Where does the cell get energy from mitochondria?")
        XCTAssertTrue(reply.contains("produce energy"), reply)
    }

    func testTutorSmallTalkAndOffTopic() {
        let hi = OfflineProvider.reply(notes: SampleNotes.text, title: "Bio", history: [], question: "hi")
        XCTAssertTrue(hi.hasPrefix("Hi!"), hi)
        let thanks = OfflineProvider.reply(notes: SampleNotes.text, history: [], question: "Thanks!")
        XCTAssertTrue(thanks.hasPrefix("You're welcome"), thanks)

        let offTopic = OfflineProvider.reply(notes: SampleNotes.text, title: "Bio", history: [], question: "What is the capital of France?")
        XCTAssertTrue(offTopic.hasPrefix("I couldn't find that in “Bio”"), offTopic)
        XCTAssertTrue(offTopic.contains(OfflineProvider.smarterTutorTip))
        let again = OfflineProvider.reply(notes: SampleNotes.text, history: turns([(true, "x"), (false, offTopic)]), question: "Who won the World Cup?")
        XCTAssertFalse(again.contains(OfflineProvider.smarterTutorTip), again)
    }

    func testTutorTextRendersMarkdown() {
        let text = TutorText.attributed("## Osmosis\n* **Water** moves\nFill in: The _____ stores DNA")
        XCTAssertEqual(String(text.characters), "Osmosis\n• Water moves\nFill in: The _____ stores DNA")
        XCTAssertTrue(text.runs.contains { $0.inlinePresentationIntent == .stronglyEmphasized })
    }
}
