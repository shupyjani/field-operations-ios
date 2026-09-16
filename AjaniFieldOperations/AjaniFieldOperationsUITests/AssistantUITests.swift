import XCTest

/// The assistant, exercised through the interface a practitioner uses.
@MainActor
final class AssistantUITests: XCTestCase {
    private enum ID {
        static let moreAssistant = "more.assistantAction"
        static let screen = "assistant.screen"
        static let welcome = "assistant.welcome"
        static let input = "assistant.input"
        static let send = "assistant.send"
        static let reply = "assistant.reply"
        static let userMessage = "assistant.userMessage"
        static let replySource = "assistant.replySource"
        static let clearAction = "assistant.clearAction"
        static let clearConfirm = "assistant.clearConfirm"
        static let resetAction = "more.resetAction"
        static let resetConfirm = "more.resetConfirm"

        static func suggestion(_ question: String) -> String { "assistant.suggestion.\(question)" }
    }

    private let timeout: TimeInterval = 20

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func launchApp() -> XCUIApplication {
        let app = XCUIApplication()
        // Keeps the app on built-in guidance, so no automated run ever makes a
        // real provider request.
        app.launchArguments += ["ajani-assistant-offline"]
        app.launch()
        // Tapping a tab before the app has settled sends the tap nowhere, and
        // the screen it should have opened never appears.
        XCTAssertTrue(app.tabBars.buttons["More"].waitForExistence(timeout: timeout))
        return app
    }

    /// Opens the assistant from More.
    ///
    /// The tab is tapped only once it is hittable, and tapped again if the More
    /// screen did not appear: on the first launch after a build the first tap
    /// can land before the app has settled, and a tap that lands nowhere leaves
    /// the screen it should have opened absent rather than late.
    @discardableResult
    private func openAssistant(in app: XCUIApplication) -> XCUIElement {
        let more = app.tabBars.buttons["More"]
        XCTAssertTrue(waitForHittable(more))
        more.tap()

        let open = app.buttons[ID.moreAssistant]
        if !open.waitForExistence(timeout: 10) {
            more.tap()
            XCTAssertTrue(open.waitForExistence(timeout: timeout), "More never offered the assistant")
        }
        if !open.isHittable { app.swipeUp() }
        open.tap()

        let screen = app.scrollViews[ID.screen]
        XCTAssertTrue(screen.waitForExistence(timeout: timeout))
        return screen
    }

    private func waitForHittable(_ element: XCUIElement) -> Bool {
        wait(NSPredicate(format: "exists == true AND hittable == true"), on: element)
    }

    private func replies(in app: XCUIApplication) -> XCUIElementQuery {
        app.descendants(matching: .any).matching(identifier: ID.reply)
    }

    private func firstReply(in app: XCUIApplication) -> XCUIElement {
        replies(in: app).firstMatch
    }

    @discardableResult
    private func waitForReplies(atLeast count: Int, in app: XCUIApplication) -> Bool {
        wait(NSPredicate(format: "count >= %d", count), on: replies(in: app))
    }

    @discardableResult
    private func waitForReplies(exactly count: Int, in app: XCUIApplication) -> Bool {
        wait(NSPredicate(format: "count == %d", count), on: replies(in: app))
    }

    // MARK: - Entry

    func testMoreOffersTheAssistantBetweenPreferencesAndApplication() throws {
        let app = launchApp()
        app.tabBars.buttons["More"].tap()

        let preferences = app.staticTexts["Preferences"]
        let assistant = app.staticTexts["Ajani Assistant"]
        let application = app.staticTexts["Application"]

        XCTAssertTrue(preferences.waitForExistence(timeout: timeout))
        XCTAssertTrue(assistant.waitForExistence(timeout: timeout))
        XCTAssertTrue(application.waitForExistence(timeout: timeout))

        XCTAssertLessThan(preferences.frame.minY, assistant.frame.minY)
        XCTAssertLessThan(assistant.frame.minY, application.frame.minY)

        XCTAssertTrue(app.staticTexts["Ask about the round, or how a control works."].exists)
        XCTAssertTrue(app.buttons[ID.moreAssistant].exists)
    }

    func testOpeningTheAssistantShowsItsWelcomeAndBackControl() throws {
        let app = launchApp()
        openAssistant(in: app)

        XCTAssertTrue(app.descendants(matching: .any)[ID.welcome].waitForExistence(timeout: timeout))
        XCTAssertTrue(app.navigationBars["Ajani Assistant"].exists)
        // A drill-down, so it carries a real back control rather than a tab.
        XCTAssertTrue(app.navigationBars.buttons.element(boundBy: 0).exists)

        // Nothing has been answered yet, so no source is claimed.
        XCTAssertFalse(app.descendants(matching: .any)[ID.replySource].exists)
    }

    // MARK: - Asking

    func testASuggestedQuestionIsAnswered() throws {
        let app = launchApp()
        openAssistant(in: app)

        let suggestion = app.buttons[ID.suggestion("Who is my next visit?")]
        XCTAssertTrue(suggestion.waitForExistence(timeout: timeout))
        if !suggestion.isHittable { app.swipeUp() }
        suggestion.tap()

        waitForReply(containing: "Priya Raman", in: app)
    }

    func testATypedQuestionIsAnsweredAndTheFieldIsCleared() throws {
        let app = launchApp()
        openAssistant(in: app)

        let input = app.textFields[ID.input]
        XCTAssertTrue(input.waitForExistence(timeout: timeout))

        // Nothing to send yet.
        XCTAssertFalse(app.buttons[ID.send].isEnabled)

        input.tap()
        XCTAssertTrue(app.keyboards.element.waitForExistence(timeout: timeout))
        input.typeText("How many visits are left?")

        let send = app.buttons[ID.send]
        XCTAssertTrue(waitForEnabled(send))
        send.tap()

        waitForReply(containing: "5 visits remain", in: app)

        // The composer empties, so the question is not sent twice.
        XCTAssertTrue(waitForDisabled(app.buttons[ID.send]))
    }

    func testTheReplySourceIsStatedHonestly() throws {
        let app = launchApp()
        openAssistant(in: app)

        let suggestion = app.buttons[ID.suggestion("Which visit is currently active?")]
        XCTAssertTrue(suggestion.waitForExistence(timeout: timeout))
        if !suggestion.isHittable { app.swipeUp() }
        suggestion.tap()

        let source = app.descendants(matching: .any).matching(identifier: ID.replySource).firstMatch
        XCTAssertTrue(source.waitForExistence(timeout: timeout))
        // This run is held to built-in guidance, so the answer is built-in and
        // must not be presented as a model response.
        XCTAssertEqual(source.value as? String, "Built-in guidance")
        XCTAssertFalse(source.label.contains("AI response"))
    }

    func testAStructuredSelectionAndItsRefinementAreAnswered() throws {
        let app = launchApp()
        openAssistant(in: app)

        ask("Which visits after midday are still planned?", in: app)
        waitForReply(containing: "3 matching visits", in: app)

        // The refinement counts what the previous answer selected rather than
        // recounting the round.
        ask("How many are there?", in: app)
        waitForReply(containing: "the same ones as the previous answer", in: app)
    }

    func testARecordedPropertyIsReadBackAndAnAbsentOneIsNot() throws {
        let app = launchApp()
        openAssistant(in: app)

        ask("How long are Sunita's seated exercises?", in: app)
        waitForReply(containing: "10 minutes", in: app)

        // Nothing on the round records a dose, and that is said rather than
        // filled in.
        ask("What dose is recorded for Halina?", in: app)
        waitForReply(containing: "does not specify a dose", in: app)
    }

    func testAFollowUpKeepsItsReferent() throws {
        let app = launchApp()
        openAssistant(in: app)

        ask("Does anyone have a walking task?", in: app)
        waitForReply(containing: "Ivor Bankole", in: app)

        ask("Has that task been completed?", in: app)
        // "task is unchecked" belongs to the follow-up alone; the search that
        // preceded it reports the same task with different wording.
        waitForReply(containing: "task is unchecked", in: app)
    }

    func testAClinicalQuestionIsRefusedInPlace() throws {
        let app = launchApp()
        openAssistant(in: app)

        ask("What dose should I give Priya?", in: app)

        waitForReply(containing: "cannot give clinical advice", in: app)
    }

    // MARK: - Clearing

    func testClearingTheConversationAsksFirst() throws {
        let app = launchApp()
        openAssistant(in: app)

        // Nothing to clear yet.
        XCTAssertFalse(app.buttons[ID.clearAction].isEnabled)

        ask("Who is my next visit?", in: app)
        XCTAssertTrue(waitForReplies(atLeast: 1, in: app))

        let clear = app.buttons[ID.clearAction]
        XCTAssertTrue(waitForEnabled(clear))
        clear.tap()

        // An accidental tap does not erase the history.
        let keep = app.alerts.buttons["Keep conversation"].firstMatch
        XCTAssertTrue(keep.waitForExistence(timeout: timeout))
        keep.tap()
        XCTAssertTrue(waitForReplies(atLeast: 1, in: app), "Keeping the conversation must leave it intact")

        clear.tap()
        let confirm = app.alerts.buttons[ID.clearConfirm].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: timeout))
        confirm.tap()

        XCTAssertTrue(waitForReplies(exactly: 0, in: app), "Clearing must empty the transcript")
        XCTAssertTrue(app.descendants(matching: .any)[ID.welcome].waitForExistence(timeout: timeout))
    }

    func testResettingTheRoundClearsTheConversation() throws {
        let app = launchApp()
        openAssistant(in: app)

        ask("Who is my next visit?", in: app)
        XCTAssertTrue(firstReply(in: app).waitForExistence(timeout: timeout))

        // Back to More, then reset the round.
        app.navigationBars.buttons.element(boundBy: 0).tap()

        let reset = app.buttons[ID.resetAction]
        XCTAssertTrue(reset.waitForExistence(timeout: timeout))
        if !reset.isHittable { app.swipeUp() }
        reset.tap()

        let confirm = app.buttons[ID.resetConfirm].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: timeout))
        confirm.tap()

        openAssistant(in: app)
        XCTAssertTrue(app.descendants(matching: .any)[ID.welcome].waitForExistence(timeout: timeout))
        XCTAssertFalse(app.descendants(matching: .any)[ID.reply].exists)
    }

    // MARK: - Live state

    func testTheAssistantReflectsWorkDoneInTheApp() throws {
        let app = launchApp()

        // Complete the visit in hand, which has outstanding tasks.
        let action = app.buttons["today.upNext.action"]
        XCTAssertTrue(action.waitForExistence(timeout: timeout))
        action.tap()
        let confirm = app.alerts.buttons["completion.confirm"].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: timeout))
        confirm.tap()

        openAssistant(in: app)
        ask("Who is my next visit?", in: app)

        waitForReply(containing: "Ivor Bankole", in: app)
    }

    // MARK: - Helpers

    /// Types a question and sends it, checking that what landed in the field is
    /// what was meant — a dropped keystroke would otherwise ask something else
    /// and the answer would be judged against the wrong question.
    private func ask(_ question: String, in app: XCUIApplication) {
        let input = app.textFields[ID.input]
        XCTAssertTrue(input.waitForExistence(timeout: timeout))
        input.tap()
        XCTAssertTrue(app.keyboards.element.waitForExistence(timeout: timeout))
        input.typeText(question)

        if (input.value as? String) != question {
            input.press(forDuration: 1.0)
            if app.menuItems["Select All"].waitForExistence(timeout: 3) {
                app.menuItems["Select All"].tap()
            }
            input.typeText(question)
        }
        XCTAssertTrue(
            wait(NSPredicate(format: "value == %@", question), on: input),
            "The question typed into the field was not the question meant"
        )

        let send = app.buttons[ID.send]
        XCTAssertTrue(waitForEnabled(send))
        send.tap()
    }

    /// Waits until some reply in the transcript contains `fragment`.
    ///
    /// Matched on content rather than position: SwiftUI may render a message as
    /// more than one element, so an index into the transcript is not a stable
    /// way to name the answer under test.
    private func waitForReply(containing fragment: String, in app: XCUIApplication) {
        let matching = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier == %@ AND label CONTAINS %@", ID.reply, fragment)
        )
        XCTAssertTrue(
            wait(NSPredicate(format: "count > 0"), on: matching),
            "No reply contained \u{201C}\(fragment)\u{201D}"
        )
    }

    private func waitForEnabled(_ element: XCUIElement) -> Bool {
        wait(NSPredicate(format: "isEnabled == true"), on: element)
    }

    private func waitForDisabled(_ element: XCUIElement) -> Bool {
        wait(NSPredicate(format: "isEnabled == false"), on: element)
    }

    private func wait(_ predicate: NSPredicate, on object: Any) -> Bool {
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: object)
        return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
    }
}
