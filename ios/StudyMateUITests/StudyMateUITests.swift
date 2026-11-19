import XCTest

final class StudyMateUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-uiTesting"]
        app.launch()
    }

    func testCreateDeckFromPastedNotesAndStudyFlashcards() {
        app.buttons["emptyStateNewDeckButton"].tap()
        let title = app.textFields["deckTitleField"]
        title.tap()
        title.typeText("Chemistry")
        let notes = app.textViews["notesEditor"]
        notes.tap()
        notes.typeText("Photosynthesis is the process plants use to make food from light. Osmosis is the movement of water across a membrane.")
        snapshot("1-new-deck")
        app.buttons["generateButton"].tap()

        XCTAssertTrue(app.buttons["flashcardsLink"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.navigationBars["Chemistry"].exists)
        snapshot("2-deck")
        app.buttons["flashcardsLink"].tap()

        let card = app.buttons["flashcard"]
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        XCTAssertEqual(card.label, "What is Photosynthesis?")
        card.tap()
        XCTAssertTrue(card.label.contains("process plants use"), card.label)
        snapshot("3-flashcard-answer")
        app.buttons["gotItButton"].tap()
        XCTAssertEqual(card.label, "What is Osmosis?")
        app.buttons["stillLearningButton"].tap()

        XCTAssertTrue(app.staticTexts["sessionComplete"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["sessionSummary"].label, "You knew 1 of 2 cards.")
        XCTAssertTrue(app.buttons["reviewMissedButton"].exists)
    }

    func testQuizFromSampleNotes() {
        createSampleDeck()
        app.buttons["quizLink"].tap()

        var answered = 0
        while !app.staticTexts["quizScore"].exists {
            XCTAssertTrue(app.staticTexts["quizQuestion"].waitForExistence(timeout: 5))
            app.buttons["quizOption_0"].tap()
            XCTAssertTrue(app.staticTexts["quizFeedback"].waitForExistence(timeout: 5))
            if answered == 0 { snapshot("4-quiz") }
            app.buttons["quizNextButton"].tap()
            answered += 1
            XCTAssertLessThan(answered, 20)
        }
        XCTAssertTrue(app.staticTexts["quizScore"].label.hasSuffix("/ \(answered)"))
        snapshot("5-quiz-score")
    }

    func testQuizRetryMissedQuestionsKeepsFullQuizScore() {
        createSampleDeck()
        app.buttons["quizLink"].tap()

        var missedPrompt: String?
        var total = 0
        while !app.staticTexts["quizScore"].exists {
            XCTAssertTrue(app.staticTexts["quizQuestion"].waitForExistence(timeout: 5))
            let prompt = app.staticTexts["quizQuestion"].label
            if missedPrompt == nil {
                missedPrompt = prompt
                answer(prompt, correctly: false)
                XCTAssertTrue(app.staticTexts["quizFeedback"].label.hasPrefix("Not quite"))
            } else {
                answer(prompt, correctly: true)
                XCTAssertEqual(app.staticTexts["quizFeedback"].label, "Correct!")
            }
            app.buttons["quizNextButton"].tap()
            total += 1
            XCTAssertLessThan(total, 20)
        }
        XCTAssertEqual(app.staticTexts["quizScore"].label, "\(total - 1) / \(total)")
        XCTAssertEqual(app.descendants(matching: .any).matching(identifier: "quizMissedRow").count, 1)
        snapshot("5-quiz-review")

        app.buttons["quizRetryMissedButton"].tap()
        XCTAssertEqual(app.staticTexts["quizProgress"].label, "Question 1 of 1")
        XCTAssertEqual(app.staticTexts["quizQuestion"].label, missedPrompt)
        answer(app.staticTexts["quizQuestion"].label, correctly: true)
        app.buttons["quizNextButton"].tap()
        XCTAssertEqual(app.staticTexts["quizScore"].label, "1 / 1")
        XCTAssertFalse(app.buttons["quizRetryMissedButton"].exists)

        app.buttons["quizRetryButton"].tap()
        XCTAssertEqual(app.staticTexts["quizProgress"].label, "Question 1 of \(total)")
        XCTAssertEqual(app.staticTexts["quizRunningScore"].label, "Score: 0")

        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.staticTexts["Last quiz: \(total - 1) / \(total)"].waitForExistence(timeout: 5))
    }

    func testTutorAnswersQuestionAboutNotes() {
        createSampleDeck()
        app.buttons["tutorLink"].tap()

        let input = app.textFields["chatInput"]
        XCTAssertTrue(input.waitForExistence(timeout: 5))
        input.tap()
        input.typeText("What do ribosomes do?")
        app.buttons["chatSendButton"].tap()

        XCTAssertTrue(app.staticTexts["userMessage"].waitForExistence(timeout: 5))
        let reply = app.staticTexts.matching(identifier: "assistantMessage").element(boundBy: 1)
        XCTAssertTrue(reply.waitForExistence(timeout: 10))
        XCTAssertTrue(reply.label.contains("build proteins"), reply.label)
        snapshot("6-tutor")
    }

    func testSettingsShowsActiveEngine() {
        app.buttons["settingsButton"].tap()
        let active = app.staticTexts["activeEngineLabel"].exists ? app.staticTexts["activeEngineLabel"] : app.otherElements["activeEngineLabel"]
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Offline mode"].exists || active.label.contains("Offline mode"))
        snapshot("7-settings")
        app.buttons["settingsDoneButton"].tap()
        XCTAssertTrue(app.buttons["emptyStateNewDeckButton"].waitForExistence(timeout: 5))
    }

    func testDeckAppearsInLibrary() {
        createSampleDeck()
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.staticTexts["Biology – The Cell"].waitForExistence(timeout: 5))
        snapshot("0-library")
    }

    private func createSampleDeck() {
        app.buttons["newDeckButton"].tap()
        app.buttons["sampleNotesButton"].tap()
        app.buttons["generateButton"].tap()
        XCTAssertTrue(app.buttons["flashcardsLink"].waitForExistence(timeout: 10))
    }

    private static let sampleAnswers = [
        "What is the cell?": "The basic unit of life",
        "What is the nucleus?": "The control center of the cell that stores DNA",
        "What are Mitochondria?": "Organelles that produce energy for the cell through respiration",
        "What are Ribosomes?": "Tiny structures that build proteins",
        "What is Osmosis?": "The movement of water across a semi-permeable membrane",
        "What is Photosynthesis?": "The process plants use to turn sunlight, water and carbon dioxide into glucose and oxygen",
        "What are Chloroplasts?": "Found in plant cells and contain chlorophyll",
        "Fill in the blank: The cell _____ controls what enters and leaves the cell": "membrane",
    ]

    private func answer(_ prompt: String, correctly: Bool) {
        let expected = try? XCTUnwrap(Self.sampleAnswers[prompt], "Unknown question: \(prompt)")
        let options = (0..<4).map { app.buttons["quizOption_\($0)"] }.filter(\.exists)
        let option = options.first { ($0.label == expected) == correctly }
        XCTAssertNotNil(option, prompt)
        option?.tap()
        XCTAssertTrue(app.staticTexts["quizFeedback"].waitForExistence(timeout: 5))
    }

    private func snapshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
