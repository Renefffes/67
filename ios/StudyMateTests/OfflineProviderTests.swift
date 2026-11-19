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

    func testNumbersAtLineStartAreKept() {
        XCTAssertEqual(OfflineProvider.sentences(in: "3.14 is the value of pi"), ["3.14 is the value of pi"])
        XCTAssertEqual(OfflineProvider.sentences(in: "-40 degrees is where both scales meet"), ["-40 degrees is where both scales meet"])
        XCTAssertEqual(OfflineProvider.sentences(in: "1. Mitosis splits cells\n- Meiosis makes gametes"), ["Mitosis splits cells", "Meiosis makes gametes"])
    }

    func testSummaryCardIsNotTurnedIntoQuiz() {
        let set = OfflineProvider.studySet(from: "Cells", title: "Bio")
        XCTAssertTrue(set.quiz.isEmpty)
    }

    func testTutorQuizHidesAnswerThenChecksIt() {
        let notes = "Osmosis is the movement of water across a membrane."
        let question = OfflineProvider.reply(notes: notes, history: [], question: "Quiz me on this")
        XCTAssertTrue(question.hasPrefix("Quick question: What is Osmosis?"), question)
        XCTAssertFalse(question.contains("movement of water"))
        let history = [TutorTurn(isUser: true, text: "Quiz me on this"), TutorTurn(isUser: false, text: question)]
        let right = OfflineProvider.reply(notes: notes, history: history, question: "water moving across a membrane")
        XCTAssertTrue(right.hasPrefix("Nice, that's right!"), right)
        let wrong = OfflineProvider.reply(notes: notes, history: history, question: "cell division")
        XCTAssertTrue(wrong.hasPrefix("Not quite."), wrong)
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
}
