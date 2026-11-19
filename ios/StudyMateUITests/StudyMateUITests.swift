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

    func testFirstLaunchSampleNotesShortcut() {
        XCTAssertTrue(app.buttons["emptyStateSettingsButton"].exists)
        app.buttons["emptyStateSampleButton"].tap()
        XCTAssertEqual(app.textFields["deckTitleField"].value as? String, "Biology – The Cell")
        XCTAssertTrue(app.buttons["generateButton"].isEnabled)
        app.buttons["generateButton"].tap()
        XCTAssertTrue(app.buttons["flashcardsLink"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.navigationBars["Biology – The Cell"].exists)
    }

    func testSettingsWarnsUntilGeminiKeyIsSaved() {
        app.buttons["settingsButton"].tap()
        app.buttons["enginePicker"].firstMatch.tap()
        app.buttons["Google Gemini"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["engineWarning"].waitForExistence(timeout: 5))
        XCTAssertTrue(activeEngineLabel.label.contains("Offline mode"), activeEngineLabel.label)

        let field = app.textFields["geminiKeyField"]
        field.tap()
        field.typeText("sk-wrong")
        XCTAssertTrue(app.staticTexts["geminiKeyFormatHint"].exists)
        field.typeText(String(repeating: "\u{8}", count: 8) + "AIzaTestKey1234")
        XCTAssertFalse(app.staticTexts["geminiKeyFormatHint"].exists)
        app.buttons["saveGeminiKeyButton"].tap()

        XCTAssertTrue(app.descendants(matching: .any)["geminiKeySaved"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["engineWarning"].exists)
        XCTAssertTrue(activeEngineLabel.label.contains("Google Gemini"), activeEngineLabel.label)
        snapshot("8-settings-gemini-key")

        app.buttons["settingsDoneButton"].tap()
        app.buttons["settingsButton"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["geminiKeySaved"].waitForExistence(timeout: 5))
        app.buttons["removeGeminiKeyButton"].tap()
        XCTAssertTrue(app.textFields["geminiKeyField"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["engineWarning"].exists)
    }

    func testAppleIntelligenceChoiceExplainsFallback() {
        app.buttons["settingsButton"].tap()
        app.buttons["enginePicker"].firstMatch.tap()
        app.buttons["Apple Intelligence"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["engineWarning"].waitForExistence(timeout: 5))
        XCTAssertTrue(activeEngineLabel.label.contains("Offline mode"), activeEngineLabel.label)
    }

    func testSearchAndDeleteDecks() {
        createSampleDeck()
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.buttons["newDeckButton"].tap()
        let title = app.textFields["deckTitleField"]
        title.tap()
        title.typeText("Chemistry")
        let notes = app.textViews["notesEditor"]
        notes.tap()
        notes.typeText("Osmosis is the movement of water across a membrane.")
        app.buttons["generateButton"].tap()
        XCTAssertTrue(app.buttons["flashcardsLink"].waitForExistence(timeout: 10))
        app.navigationBars.buttons.element(boundBy: 0).tap()

        let search = app.searchFields.firstMatch
        if !search.waitForExistence(timeout: 2) { app.swipeDown() }
        search.tap()
        search.typeText("Chem")
        XCTAssertTrue(app.staticTexts["Chemistry"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Biology – The Cell"].exists)
        search.typeText(String(repeating: "\u{8}", count: 4))

        let biology = app.staticTexts["Biology – The Cell"]
        XCTAssertTrue(biology.waitForExistence(timeout: 5))
        biology.swipeLeft()
        app.buttons["Delete"].firstMatch.tap()
        XCTAssertTrue(app.buttons["confirmDeleteDeckButton"].firstMatch.waitForExistence(timeout: 5))
        app.buttons["confirmDeleteDeckButton"].firstMatch.tap()
        XCTAssertFalse(biology.waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["Chemistry"].exists)
    }

    func testEmptyStateReachableWithLargestText() {
        app.terminate()
        app.launchArguments = ["-uiTesting", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        let create = app.buttons["emptyStateNewDeckButton"]
        XCTAssertTrue(create.waitForExistence(timeout: 5))
        if !create.isHittable { app.swipeUp() }
        XCTAssertTrue(create.isHittable)
        create.tap()
        XCTAssertTrue(app.textFields["deckTitleField"].waitForExistence(timeout: 5))
    }

    private var activeEngineLabel: XCUIElement {
        app.staticTexts["activeEngineLabel"].exists ? app.staticTexts["activeEngineLabel"] : app.otherElements["activeEngineLabel"]
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

    func testShortNotesShowHintAndSuggestedTitle() {
        app.buttons["emptyStateNewDeckButton"].tap()
        let notes = app.textViews["notesEditor"]
        XCTAssertTrue(notes.waitForExistence(timeout: 5))
        notes.tap()
        notes.typeText("Osmosis")
        let count = app.staticTexts["wordCountLabel"]
        XCTAssertTrue(count.waitForExistence(timeout: 5))
        XCTAssertTrue(count.label.hasPrefix("1 word ·"), count.label)
        XCTAssertEqual(app.textFields["deckTitleField"].placeholderValue, "Osmosis")
        app.buttons["Done"].tap()
        XCTAssertTrue(app.buttons["generateButton"].isEnabled)
    }
}
