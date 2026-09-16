import XCTest

/// The operational rules, exercised through the interface a practitioner uses.
@MainActor
final class VisitWorkflowUITests: XCTestCase {
    private enum ID {
        static let upNextVisit = "today.upNext.visit"
        static let upNextAction = "today.upNext.action"
        static let primaryAction = "visitDetail.primaryAction"
        static let cancelAction = "visitDetail.cancelAction"
        static let returnAction = "visitDetail.returnAction"
        static let cancelledNotice = "visitDetail.cancelledNotice"
        static let cancellationReason = "visitDetail.cancellationReason"
        static let taskLock = "visitDetail.taskLock"
        static let sheetNote = "cancelSheet.note"
        static let sheetConfirm = "cancelSheet.confirm"
        static let sheetRequirement = "cancelSheet.requirement"
        static let resetAction = "more.resetAction"
        static let resetConfirm = "more.resetConfirm"

        static func visitRow(_ reference: String) -> String { "visitRow.\(reference)" }
        static func reason(_ title: String) -> String { "cancelSheet.reason.\(title)" }
        static func task(_ title: String) -> String { "visitTask.\(title)" }
    }

    private let timeout: TimeInterval = 20

    /// Mirrors the app's cancellation note limit, so the boundary stays in step.
    private enum CancellationLimits {
        static let note = 200
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func launchApp() -> XCUIApplication {
        let app = XCUIApplication()
        // Keeps the app on built-in guidance, so no automated run ever makes a
        // real provider request.
        app.launchArguments += ["ajani-assistant-offline"]
        app.launch()
        return app
    }

    /// Opens a visit from the Visits list.
    private func openVisit(_ reference: String, in app: XCUIApplication) {
        app.tabBars.buttons["Visits"].tap()
        let row = app.buttons[ID.visitRow(reference)]
        XCTAssertTrue(row.waitForExistence(timeout: timeout))
        row.tap()
    }

    private func tap(_ element: XCUIElement, in app: XCUIApplication) {
        if !element.isHittable { app.swipeUp() }
        let hittable = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "isHittable == true"),
            object: element
        )
        XCTAssertEqual(XCTWaiter().wait(for: [hittable], timeout: timeout), .completed)
        element.tap()
    }

    // MARK: - Cancelling

    func testCancellingAPlannedVisitRecordsTheReason() throws {
        let app = launchApp()
        openVisit("AV-1044", in: app)

        let cancel = app.buttons[ID.cancelAction]
        XCTAssertTrue(cancel.waitForExistence(timeout: timeout))
        tap(cancel, in: app)

        let reason = app.buttons[ID.reason("Family cancelled")]
        XCTAssertTrue(reason.waitForExistence(timeout: timeout))
        reason.tap()

        confirmCancellation(in: app)

        // The visit closes, says so, and keeps the reason on the record.
        XCTAssertTrue(app.staticTexts[ID.cancelledNotice].waitForExistence(timeout: timeout))
        XCTAssertTrue(app.descendants(matching: .any)[ID.cancellationReason].exists)
        XCTAssertFalse(app.buttons[ID.primaryAction].exists)
        XCTAssertFalse(app.buttons[ID.cancelAction].exists)
    }

    func testCancellingWithOtherRequiresANote() throws {
        let app = launchApp()
        openVisit("AV-1044", in: app)

        tap(app.buttons[ID.cancelAction], in: app)

        let confirm = app.buttons[ID.sheetConfirm]
        XCTAssertTrue(confirm.waitForExistence(timeout: timeout))

        // Nothing chosen yet: the action is unavailable and says what is needed.
        XCTAssertFalse(confirm.isEnabled, "Cancelling should be unavailable before a reason is chosen")
        XCTAssertTrue(app.descendants(matching: .any)[ID.sheetRequirement].exists)

        let other = app.buttons[ID.reason("Other")]
        XCTAssertTrue(other.waitForExistence(timeout: timeout))
        other.tap()

        // "Other" on its own records nothing, so it stays unavailable.
        XCTAssertFalse(confirm.isEnabled, "\"Other\" without a note should not be submittable")
        XCTAssertTrue(app.descendants(matching: .any)[ID.sheetRequirement].exists)

        // Whitespace is not a note.
        let note = app.textViews[ID.sheetNote]
        XCTAssertTrue(note.waitForExistence(timeout: timeout))
        note.tap()
        note.typeText("   ")
        XCTAssertFalse(confirm.isEnabled, "Whitespace should not satisfy the note requirement")

        note.typeText("Road closed for resurfacing")
        XCTAssertTrue(waitForEnabled(confirm))
        XCTAssertFalse(app.descendants(matching: .any)[ID.sheetRequirement].exists)

        confirm.tap()
        XCTAssertTrue(app.staticTexts[ID.cancelledNotice].waitForExistence(timeout: timeout))
    }

    func testAnApprovedReasonNeedsNoNote() throws {
        let app = launchApp()
        openVisit("AV-1044", in: app)

        tap(app.buttons[ID.cancelAction], in: app)

        let confirm = app.buttons[ID.sheetConfirm]
        XCTAssertTrue(confirm.waitForExistence(timeout: timeout))
        XCTAssertFalse(confirm.isEnabled)

        let reason = app.buttons[ID.reason("Client unavailable")]
        XCTAssertTrue(reason.waitForExistence(timeout: timeout))
        reason.tap()

        // A listed reason is enough on its own.
        XCTAssertTrue(waitForEnabled(confirm))
        XCTAssertFalse(app.descendants(matching: .any)[ID.sheetRequirement].exists)
    }

    func testANoteOverTheLimitBlocksSubmission() throws {
        let app = launchApp()
        openVisit("AV-1044", in: app)

        tap(app.buttons[ID.cancelAction], in: app)

        let reason = app.buttons[ID.reason("Family cancelled")]
        XCTAssertTrue(reason.waitForExistence(timeout: timeout))
        reason.tap()

        let confirm = app.buttons[ID.sheetConfirm]
        XCTAssertTrue(waitForEnabled(confirm))

        // One character past the limit takes the action away again.
        let note = app.textViews[ID.sheetNote]
        note.tap()
        note.typeText(String(repeating: "x", count: CancellationLimits.note + 1))

        XCTAssertTrue(waitForDisabled(confirm), "A note over the limit should block submission")
        XCTAssertTrue(app.descendants(matching: .any)[ID.sheetRequirement].exists)
        XCTAssertFalse(app.staticTexts[ID.cancelledNotice].exists)
    }

    func testAnArrivedVisitOffersNoCancellation() throws {
        let app = launchApp()
        // Priya Raman is already on site.
        openVisit("AV-1043", in: app)

        XCTAssertTrue(app.buttons[ID.primaryAction].waitForExistence(timeout: timeout))
        XCTAssertFalse(app.buttons[ID.cancelAction].exists)
        XCTAssertFalse(app.buttons[ID.returnAction].exists)
    }

    // MARK: - One active visit

    func testStartingASecondVisitIsRefused() throws {
        let app = launchApp()
        // Priya Raman is arrived, so nothing else may be started.
        openVisit("AV-1044", in: app)

        let action = app.buttons[ID.primaryAction]
        XCTAssertTrue(action.waitForExistence(timeout: timeout))
        XCTAssertEqual(action.label, "Start travelling")
        tap(action, in: app)

        // The refusal names the visit holding the round up.
        let alert = app.alerts.firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: timeout))
        XCTAssertTrue(alert.staticTexts["Priya Raman is still active"].exists)
        alert.buttons["Stay here"].tap()

        // Neither visit moved.
        XCTAssertTrue(waitForLabel("Start travelling", on: action))
    }

    // MARK: - Return to planned

    func testAnEnRouteVisitCanBeReturnedToPlanned() throws {
        let app = launchApp()

        // Close the visit in hand so another can be started.
        let upNext = app.buttons[ID.upNextAction]
        XCTAssertTrue(upNext.waitForExistence(timeout: timeout))
        tap(upNext, in: app)
        let confirm = app.alerts.buttons["completion.confirm"].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: timeout))
        confirm.tap()
        XCTAssertTrue(waitForLabel("Start travelling", on: app.buttons[ID.upNextAction]))

        openVisit("AV-1044", in: app)
        let action = app.buttons[ID.primaryAction]
        XCTAssertTrue(action.waitForExistence(timeout: timeout))
        tap(action, in: app)
        XCTAssertTrue(waitForLabel("Mark as arrived", on: action))

        // Only en route offers the way back.
        let returnToPlanned = app.buttons[ID.returnAction]
        XCTAssertTrue(returnToPlanned.waitForExistence(timeout: timeout))
        tap(returnToPlanned, in: app)

        // Scoped to the alert: the detail screen carries a button of the same
        // name, which is the one that opened this question.
        let confirmReturn = app.alerts.buttons["return.confirm"].firstMatch
        XCTAssertTrue(confirmReturn.waitForExistence(timeout: timeout))
        confirmReturn.tap()

        XCTAssertTrue(waitForLabel("Start travelling", on: action))
        XCTAssertFalse(app.buttons[ID.returnAction].exists)
    }

    // MARK: - Task locking

    func testTasksAreLockedUntilArrival() throws {
        let app = launchApp()
        openVisit("AV-1044", in: app)

        let lock = app.descendants(matching: .any)[ID.taskLock]
        XCTAssertTrue(lock.waitForExistence(timeout: timeout))

        let task = app.buttons[ID.task("Walk the hallway circuit twice")]
        XCTAssertTrue(task.waitForExistence(timeout: timeout))
        XCTAssertEqual(task.value as? String, "Not done")
        XCTAssertFalse(task.isEnabled, "A planned visit's checklist should not be editable")

        // The refusal is real, not only visual: tapping records nothing.
        if task.isHittable { task.tap() }
        XCTAssertEqual(task.value as? String, "Not done")
    }

    func testTasksBecomeEditableOnArrival() throws {
        let app = launchApp()
        // Priya Raman has already arrived, so her checklist is live.
        openVisit("AV-1043", in: app)

        XCTAssertFalse(app.descendants(matching: .any)[ID.taskLock].exists)

        let task = app.buttons[ID.task("Check wound dressing")]
        XCTAssertTrue(task.waitForExistence(timeout: timeout))
        XCTAssertTrue(task.isEnabled)
        XCTAssertEqual(task.value as? String, "Not done")

        tap(task, in: app)

        let done = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value == %@", "Done"),
            object: task
        )
        XCTAssertEqual(XCTWaiter().wait(for: [done], timeout: timeout), .completed)
    }

    // MARK: - More

    func testMoreSectionsAreOrderedForTheProduct() throws {
        let app = launchApp()
        app.tabBars.buttons["More"].tap()

        let preferences = app.staticTexts["Preferences"]
        let application = app.staticTexts["Application"]
        let demonstration = app.staticTexts["Demonstration round"]

        XCTAssertTrue(preferences.waitForExistence(timeout: timeout))
        XCTAssertTrue(application.waitForExistence(timeout: timeout))
        XCTAssertTrue(demonstration.waitForExistence(timeout: timeout))

        // Preferences, then Application, with the demonstration utility last.
        XCTAssertLessThan(preferences.frame.minY, application.frame.minY)
        XCTAssertLessThan(application.frame.minY, demonstration.frame.minY)
    }

    func testApplicationCardShowsOnlyTheProductName() throws {
        let app = launchApp()
        app.tabBars.buttons["More"].tap()

        XCTAssertTrue(app.staticTexts["Application"].waitForExistence(timeout: timeout))
        XCTAssertTrue(app.staticTexts["Ajani Mobile"].exists)

        // The version and build rows were removed with the label they sat under.
        XCTAssertFalse(app.staticTexts["Version"].exists)
        XCTAssertFalse(app.staticTexts["Build"].exists)
    }

    // MARK: - Reset

    func testResetRestoresTheRound() throws {
        let app = launchApp()

        // Cancel a visit, so there is something to restore.
        openVisit("AV-1044", in: app)
        tap(app.buttons[ID.cancelAction], in: app)
        let reason = app.buttons[ID.reason("Client unavailable")]
        XCTAssertTrue(reason.waitForExistence(timeout: timeout))
        reason.tap()
        confirmCancellation(in: app)
        XCTAssertTrue(app.staticTexts[ID.cancelledNotice].waitForExistence(timeout: timeout))

        // Reset from More.
        app.tabBars.buttons["More"].tap()
        let reset = app.buttons[ID.resetAction]
        XCTAssertTrue(reset.waitForExistence(timeout: timeout))
        tap(reset, in: app)

        let confirm = app.buttons[ID.resetConfirm].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: timeout))
        confirm.tap()

        // Returning to Visits lands back on the visit that was open, which is
        // planned again and offers its first step.
        app.tabBars.buttons["Visits"].tap()
        let action = app.buttons[ID.primaryAction]
        XCTAssertTrue(action.waitForExistence(timeout: timeout))
        XCTAssertEqual(action.label, "Start travelling")
        XCTAssertFalse(app.staticTexts[ID.cancelledNotice].exists)
    }

    // MARK: - Helpers

    /// Confirms a cancellation once the sheet has accepted the form.
    private func confirmCancellation(in app: XCUIApplication) {
        let confirm = app.buttons[ID.sheetConfirm]
        XCTAssertTrue(waitForEnabled(confirm), "The cancel action should become available once the form is valid")
        confirm.tap()
    }

    private func waitForEnabled(_ element: XCUIElement) -> Bool {
        wait(NSPredicate(format: "isEnabled == true"), on: element)
    }

    private func waitForDisabled(_ element: XCUIElement) -> Bool {
        wait(NSPredicate(format: "isEnabled == false"), on: element)
    }

    private func wait(_ predicate: NSPredicate, on element: XCUIElement) -> Bool {
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
    }

    private func waitForLabel(_ label: String, on element: XCUIElement) -> Bool {
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label == %@", label),
            object: element
        )
        return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
    }
}
