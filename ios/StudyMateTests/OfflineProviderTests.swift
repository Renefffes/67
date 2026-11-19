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
        XCTAssertTrue(right.hasPrefix("Correct!"), right)
        let wrong = OfflineProvider.reply(notes: notes, history: history, question: "cell division")
        XCTAssertTrue(wrong.hasPrefix("Not quite."), wrong)
    }

    func testTutorGradesAnswerThatMentionsQuiz() {
        let notes = "A quiz is a short test of knowledge."
        let question = OfflineProvider.reply(notes: notes, history: [], question: "Quiz me")
        let history = [TutorTurn(isUser: true, text: "Quiz me"), TutorTurn(isUser: false, text: question)]
        let answer = OfflineProvider.reply(notes: notes, history: history, question: "a short test of knowledge, like a quiz")
        XCTAssertTrue(answer.hasPrefix("Correct!"), answer)
        let next = OfflineProvider.reply(notes: notes, history: history, question: "quiz me again")
        XCTAssertTrue(next.hasPrefix(OfflineProvider.quizPrefix), next)
    }

    func testTutorGradesTheCardItAsked() {
        let notes = "Mitochondria produce energy. Ribosomes produce proteins. Chloroplasts capture sunlight."
        let set = OfflineProvider.studySet(from: notes, title: "")
        var history: [TutorTurn] = []
        for _ in 0..<2 {
            history.append(TutorTurn(isUser: true, text: "Quiz me"))
            history.append(TutorTurn(isUser: false, text: OfflineProvider.reply(notes: notes, history: history, question: "Quiz me")))
        }
        let answer = OfflineProvider.reply(notes: notes, history: history, question: set.flashcards[1 % set.flashcards.count].back)
        XCTAssertTrue(answer.hasPrefix("Correct!"), answer)
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

    func testTutorGradingIsStrictAboutDifferentWordsButAcceptsSymbols() {
        let titan = GeneratedCard(front: "What is Saturn's largest moon?", back: "Titan")
        XCTAssertTrue(OfflineProvider.grade(answer: "titanium", card: titan).hasPrefix("Not quite"))
        XCTAssertTrue(OfflineProvider.grade(answer: "Titan", card: titan).hasPrefix("Correct!"))
        let iron = GeneratedCard(front: "Which element has the symbol Fe?", back: "Fe (iron)")
        XCTAssertTrue(OfflineProvider.grade(answer: "Fe", card: iron).hasPrefix("Correct!"))
    }

    func testTutorGradesTheAskedCardWhenPromptsRepeat() {
        let cards = [GeneratedCard(front: "The _____ splits cells.", back: "spindle"), GeneratedCard(front: "The _____ splits cells.", back: "cleavage")]
        let history = [
            TutorTurn(isUser: false, text: "\(OfflineProvider.quizPrefix)\(cards[0].front)"),
            TutorTurn(isUser: true, text: "spindle"),
            TutorTurn(isUser: false, text: "Correct!\n\n\(OfflineProvider.quizPrefix)\(cards[1].front)"),
        ]
        XCTAssertEqual(OfflineProvider.pendingQuizCard(history: history, cards: cards)?.back, "cleavage")
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

    func testTutorQuizzesOneWordPerLineNotes() {
        let reply = OfflineProvider.reply(notes: "Mitochondria\nRibosome\nNucleus", history: [], question: "Quiz me")
        XCTAssertTrue(reply.hasPrefix(OfflineProvider.quizPrefix), reply)
    }

    func testExplainRequestDuringQuizIsNotGraded() {
        let notes = "Photosynthesis is how plants make food from light. Osmosis is the movement of water across a membrane."
        let question = OfflineProvider.reply(notes: notes, history: [], question: "Quiz me")
        let history = [TutorTurn(isUser: true, text: "Quiz me"), TutorTurn(isUser: false, text: question)]
        let reply = OfflineProvider.reply(notes: notes, history: history, question: "Explain photosynthesis")
        XCTAssertTrue(reply.contains("make food from light"), reply)
        XCTAssertFalse(reply.hasPrefix("Not quite"), reply)
    }

    func testTutorTextKeepsMultiplicationSigns() {
        XCTAssertEqual(String(TutorText.attributed("2*3*4 = 24").characters), "2*3*4 = 24")
        XCTAssertEqual(String(TutorText.attributed("a **bold** word").characters), "a bold word")
    }

    func testAnswerContainingSkipIsGraded() {
        let notes = "A jump rope is a rope used to skip."
        let question = OfflineProvider.reply(notes: notes, history: [], question: "Quiz me")
        let history = [TutorTurn(isUser: true, text: "Quiz me"), TutorTurn(isUser: false, text: question)]
        let reply = OfflineProvider.reply(notes: notes, history: history, question: "a rope used to skip")
        XCTAssertTrue(reply.hasPrefix("Correct!"), reply)
    }

    func testCardIsNotAcceptedForCar() {
        XCTAssertTrue(OfflineProvider.grade(answer: "card", card: GeneratedCard(front: "What has four wheels?", back: "Car")).hasPrefix("Not quite"))
        XCTAssertTrue(OfflineProvider.grade(answer: "divided", card: GeneratedCard(front: "What happens?", back: "Divide")).hasPrefix("Correct!"))
    }

    func testNewWhyQuestionIsNotAFollowUp() {
        let notes = "The nucleus stores DNA. Mitochondria produce energy."
        let first = OfflineProvider.reply(notes: notes, history: [], question: "What does the nucleus do?")
        let history = [TutorTurn(isUser: true, text: "What does the nucleus do?"), TutorTurn(isUser: false, text: first)]
        let reply = OfflineProvider.reply(notes: notes, history: history, question: "Why is the sky blue?")
        XCTAssertFalse(reply.contains("stores DNA"), reply)
    }

    func testTellMeMoreStaysOnTopic() {
        let notes = "The nucleus is the control center of the cell. The nucleus stores DNA. A cell membrane surrounds every cell. Cells divide by mitosis."
        let first = OfflineProvider.reply(notes: notes, history: [], question: "What is the nucleus?")
        let history = [TutorTurn(isUser: true, text: "What is the nucleus?"), TutorTurn(isUser: false, text: first)]
        let more = OfflineProvider.reply(notes: notes, history: history, question: "Tell me more")
        XCTAssertFalse(more.contains("mitosis"), more)
        XCTAssertFalse(more.contains("membrane"), more)
    }

    func testDescribeAnswerIsGraded() {
        let notes = "Osmosis is the movement of water across a membrane."
        let question = OfflineProvider.reply(notes: notes, history: [], question: "Quiz me")
        let history = [TutorTurn(isUser: true, text: "Quiz me"), TutorTurn(isUser: false, text: question)]
        let reply = OfflineProvider.reply(notes: notes, history: history, question: "Describe the movement of water across a membrane")
        XCTAssertTrue(reply.hasPrefix("Correct!"), reply)
    }
}
