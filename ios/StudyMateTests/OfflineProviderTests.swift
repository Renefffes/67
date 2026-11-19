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

    func testWrongOptionsVaryBetweenQuestions() {
        let set = OfflineProvider.studySet(from: SampleNotes.text, title: SampleNotes.title)
        let wrongSets = set.quiz.map { question in
            Set(question.options.enumerated().filter { $0.offset != question.answerIndex }.map(\.element))
        }
        XCTAssertGreaterThan(Set(wrongSets).count, wrongSets.count / 2)
    }

    func testDefinitionQuestionsOnlyOfferDefinitions() {
        let notes = "Photosynthesis is the process plants use to make food from light. Osmosis is the movement of water across a membrane."
        let set = OfflineProvider.studySet(from: notes, title: "")
        XCTAssertEqual(set.quiz.count, 2)
        for question in set.quiz {
            XCTAssertFalse(question.options.contains("Photosynthesis"), "\(question.options)")
            XCTAssertFalse(question.options.contains("Osmosis"), "\(question.options)")
        }
    }

    func testSingleDefinitionMakesNoWordSaladQuestion() {
        let set = OfflineProvider.studySet(from: "Osmosis is the movement of water across a membrane.", title: "")
        XCTAssertTrue(set.quiz.isEmpty, "\(set.quiz)")
    }

    func testBlankOptionsAreNotWordsFromTheSentence() {
        let set = OfflineProvider.studySet(from: SampleNotes.text, title: SampleNotes.title)
        let cloze = try? XCTUnwrap(set.quiz.first { $0.question.hasPrefix("Fill in the blank") })
        let sentenceWords = Set((cloze?.question ?? "").lowercased().components(separatedBy: CharacterSet.letters.inverted))
        for (offset, option) in (cloze?.options ?? []).enumerated() where offset != cloze?.answerIndex {
            XCTAssertFalse(sentenceWords.contains(option.lowercased()), option)
            XCTAssertEqual(option.first?.isLowercase, true, "Options should look like the lowercase answer: \(option)")
        }
    }

    func testTermNotesAskWhatTheTermMeans() {
        let notes = "- Mitosis: cell division producing two identical cells\n- Meiosis: cell division producing four gametes"
        let set = OfflineProvider.studySet(from: notes, title: "")
        XCTAssertEqual(set.quiz.first?.question, "What does “Mitosis” mean?")
    }

    func testShuffledQuizKeepsTheRightAnswer() {
        let items = (0..<6).map { QuizItem(id: $0, prompt: "Q\($0)", options: ["a\($0)", "b\($0)", "c\($0)", "d\($0)"], answerIndex: $0 % 4, explanation: "") }
        var generator = SeededGenerator(seed: 7)
        let shuffled = QuizItem.shuffled(items, using: &generator)
        XCTAssertEqual(Set(shuffled.map(\.id)), Set(items.map(\.id)))
        for item in shuffled {
            let original = items[item.id]
            XCTAssertEqual(item.correctAnswer, original.correctAnswer)
            XCTAssertEqual(Set(item.options), Set(original.options))
        }
        XCTAssertNotEqual(shuffled.map(\.id), items.map(\.id))
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
