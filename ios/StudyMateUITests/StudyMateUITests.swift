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

    func testTutorQuizWaitsForStudentAnswer() {
        createSampleDeck()
        app.buttons["tutorLink"].tap()
        app.buttons["Quiz me on this"].tap()

        let question = app.staticTexts.matching(identifier: "assistantMessage").element(boundBy: 1)
        XCTAssertTrue(question.waitForExistence(timeout: 10))
        XCTAssertTrue(question.label.hasPrefix("Quick question:"), question.label)
        XCTAssertFalse(question.label.contains("basic unit of life"), question.label)

        let input = app.textFields["chatInput"]
        input.tap()
        input.typeText("The basic unit of life")
        app.buttons["chatSendButton"].tap()
        let feedback = app.staticTexts.matching(identifier: "assistantMessage").element(boundBy: 2)
        XCTAssertTrue(feedback.waitForExistence(timeout: 10))
        XCTAssertTrue(feedback.label.hasPrefix("Correct!"), feedback.label)
        XCTAssertTrue(feedback.isHittable, "The newest reply should be scrolled into view")
        snapshot("8-tutor-quiz")
    }

    func testClearConversationAsksFirst() {
        createSampleDeck()
        app.buttons["tutorLink"].tap()
        app.buttons["Quiz me on this"].tap()
        XCTAssertTrue(app.staticTexts.matching(identifier: "assistantMessage").element(boundBy: 1).waitForExistence(timeout: 10))

        app.buttons["chatClearButton"].tap()
        let alert = app.alerts["Clear this conversation?"]
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        alert.buttons["Cancel"].tap()
        XCTAssertTrue(app.staticTexts.matching(identifier: "userMessage").firstMatch.exists)

        app.buttons["chatClearButton"].tap()
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        alert.buttons["Clear"].tap()
        XCTAssertTrue(app.buttons["Quiz me on this"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts.matching(identifier: "userMessage").firstMatch.exists)
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

    func testFlashcardSwipeUndoEditDeleteAndResume() {
        createSampleDeck()
        app.buttons["flashcardsLink"].tap()
        let card = app.buttons["flashcard"]
        let counter = app.staticTexts["cardCounter"]
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        XCTAssertEqual(card.label, "What is the cell?")
        XCTAssertEqual(counter.label, "Card 1 of 8")

        card.swipeRight()
        XCTAssertTrue(app.navigationBars["Flashcards"].exists, "Swiping a card must not leave the session")
        XCTAssertEqual(counter.label, "Card 2 of 8")
        XCTAssertEqual(app.staticTexts["deckProgress"].label, "1 mastered · 7 still learning")

        app.buttons["undoButton"].tap()
        XCTAssertEqual(counter.label, "Card 1 of 8")
        XCTAssertEqual(card.label, "What is the cell?")
        XCTAssertEqual(app.staticTexts["deckProgress"].label, "0 mastered · 8 still learning")

        card.swipeRight()
        XCTAssertEqual(counter.label, "Card 2 of 8")
        let secondFront = card.label

        app.buttons["cardOptionsButton"].tap()
        app.buttons["editCardButton"].tap()
        let front = app.textViews["cardFrontField"].exists ? app.textViews["cardFrontField"] : app.textFields["cardFrontField"]
        XCTAssertTrue(front.waitForExistence(timeout: 5))
        front.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: 0.5)).tap()
        front.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: secondFront.count + 5))
        front.typeText("Where is DNA stored?")
        snapshot("8-edit-card")
        app.buttons["saveCardButton"].tap()
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        XCTAssertEqual(card.label, "Where is DNA stored?")

        app.buttons["cardOptionsButton"].tap()
        app.buttons["deleteCardButton"].tap()
        let confirm = app.buttons.matching(identifier: "confirmDeleteCardButton").firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        confirm.tap()
        XCTAssertEqual(counter.label, "Card 2 of 7")
        XCTAssertNotEqual(card.label, "Where is DNA stored?")
        card.swipeLeft()
        XCTAssertEqual(counter.label, "Card 3 of 7")

        app.navigationBars["Flashcards"].buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.buttons["flashcardsLink"].waitForExistence(timeout: 5))
        app.buttons["flashcardsLink"].tap()
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        XCTAssertEqual(counter.label, "Card 1 of 6", "Coming back skips mastered cards")
        XCTAssertNotEqual(card.label, "What is the cell?")
        snapshot("9-resume")
    }

    private func createSampleDeck() {
        app.buttons["newDeckButton"].tap()
        app.buttons["sampleNotesButton"].tap()
        app.buttons["generateButton"].tap()
        XCTAssertTrue(app.buttons["flashcardsLink"].waitForExistence(timeout: 10))
    }

    private func snapshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
