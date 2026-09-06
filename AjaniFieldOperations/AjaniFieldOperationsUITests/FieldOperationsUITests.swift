import XCTest

@MainActor
final class FieldOperationsUITests: XCTestCase {
    private enum ID {
        static let todayScreen = "today.screen"
        static let upNextVisit = "today.upNext.visit"
        static let upNextAction = "today.upNext.action"
        static let visitsEmptyState = "visits.emptyState"
        static let visitDetailPrimaryAction = "visitDetail.primaryAction"
        static let visitDetailCompletedNotice = "visitDetail.completedNotice"

        static func visitRow(_ reference: String) -> String { "visitRow.\(reference)" }
    }

    /// Headroom for UI queries on a busy machine, without letting a genuine
    /// regression take minutes to surface.
    private let timeout: TimeInterval = 20

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func launchApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launch()
        return app
    }

    /// Switches to Visits and waits until the list has rendered.
    private func openVisits(in app: XCUIApplication) {
        app.tabBars.buttons["Visits"].tap()
        XCTAssertTrue(app.buttons[ID.visitRow("AV-1042")].waitForExistence(timeout: timeout))
    }

    func testAppLaunchesOnTodayWithTheShiftInView() throws {
        let app = launchApp()

        XCTAssertTrue(app.scrollViews[ID.todayScreen].waitForExistence(timeout: timeout))
        XCTAssertTrue(app.buttons[ID.upNextVisit].waitForExistence(timeout: timeout))
        XCTAssertTrue(app.tabBars.buttons["Today"].exists)
        XCTAssertTrue(app.tabBars.buttons["Visits"].exists)
        XCTAssertTrue(app.tabBars.buttons["More"].exists)
    }

    func testSwitchingBetweenTodayAndVisits() throws {
        let app = launchApp()
        XCTAssertTrue(app.buttons[ID.upNextVisit].waitForExistence(timeout: timeout))

        openVisits(in: app)

        app.tabBars.buttons["Today"].tap()
        XCTAssertTrue(app.buttons[ID.upNextVisit].waitForExistence(timeout: timeout))
    }

    func testOpeningAVisitFromTheVisitsList() throws {
        let app = launchApp()
        openVisits(in: app)

        app.buttons[ID.visitRow("AV-1042")].tap()

        // Waits on a note, which only the detail screen shows. The client name would
        // also match the list row behind it, and so can pass mid-transition.
        XCTAssertTrue(
            app.staticTexts["Prefers the kitchen door rather than the front entrance."]
                .waitForExistence(timeout: timeout)
        )
        XCTAssertTrue(app.staticTexts["Marguerite Okonjo"].exists)
        // A finished visit offers no further action.
        XCTAssertTrue(app.staticTexts[ID.visitDetailCompletedNotice].exists)
        XCTAssertFalse(app.buttons[ID.visitDetailPrimaryAction].exists)
    }

    func testCompletingAVisitStatusJourney() throws {
        let app = launchApp()
        openVisits(in: app)

        let plannedFilter = app.buttons["Planned"]
        XCTAssertTrue(plannedFilter.waitForExistence(timeout: timeout))
        plannedFilter.tap()

        let row = app.buttons[ID.visitRow("AV-1045")]
        XCTAssertTrue(row.waitForExistence(timeout: timeout))
        row.tap()

        let action = app.buttons[ID.visitDetailPrimaryAction]
        XCTAssertTrue(action.waitForExistence(timeout: timeout))
        XCTAssertEqual(action.label, "Start travelling")

        tap(action, in: app)
        XCTAssertTrue(waitForLabel("Mark as arrived", on: action))

        tap(action, in: app)
        XCTAssertTrue(waitForLabel("Complete visit", on: action))

        tap(action, in: app)
        XCTAssertTrue(app.staticTexts[ID.visitDetailCompletedNotice].waitForExistence(timeout: timeout))
        XCTAssertFalse(action.exists)
    }

    func testCompletingTheUpNextVisitFromToday() throws {
        let app = launchApp()

        let action = app.buttons[ID.upNextAction]
        XCTAssertTrue(action.waitForExistence(timeout: timeout))
        // The demonstration shift opens with one visit already on site.
        XCTAssertEqual(action.label, "Complete visit")

        tap(action, in: app)

        // Once complete, the card moves on to the next planned visit.
        XCTAssertTrue(waitForLabel("Start travelling", on: app.buttons[ID.upNextAction]))

        let upNext = app.buttons[ID.upNextVisit]
        XCTAssertTrue(upNext.waitForExistence(timeout: timeout))
        XCTAssertTrue(
            upNext.label.contains("Ivor Bassey"),
            "Up next should advance to the next planned visit, but showed: \(upNext.label)"
        )
    }

    func testSearchNarrowsTheVisitsList() throws {
        let app = launchApp()
        openVisits(in: app)

        search(for: "Noor", in: app)

        // The result summary is the only signal that filtering has actually been
        // applied: the matching row is already on screen before the search runs,
        // so waiting on it would prove nothing and leave the negative assertion
        // below racing the filter.
        XCTAssertTrue(app.staticTexts["Showing 1 of 7 visits"].waitForExistence(timeout: timeout))
        XCTAssertTrue(app.buttons[ID.visitRow("AV-1046")].exists)
        XCTAssertFalse(app.buttons[ID.visitRow("AV-1042")].exists)
    }

    func testSearchWithNoMatchesShowsAnEmptyState() throws {
        let app = launchApp()
        openVisits(in: app)

        search(for: "Zzzzz", in: app)

        XCTAssertTrue(emptyState(in: app).waitForExistence(timeout: timeout))
        XCTAssertFalse(app.buttons[ID.visitRow("AV-1042")].exists)
    }

    // MARK: - Helpers

    private func search(for query: String, in app: XCUIApplication) {
        let searchField = app.searchFields.firstMatch
        XCTAssertTrue(searchField.waitForExistence(timeout: timeout))
        searchField.tap()
        // Typing before the field has focus drops the keystrokes.
        XCTAssertTrue(app.keyboards.element.waitForExistence(timeout: timeout))
        searchField.typeText(query)
    }

    /// The empty state is the only element whose SwiftUI element type is not fixed,
    /// and it is only queried once the list is empty, so the tree is small.
    private func emptyState(in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: ID.visitsEmptyState).firstMatch
    }

    /// Taps once the element is genuinely interactive, so a tap is never sent
    /// mid-transition and silently dropped.
    private func tap(_ element: XCUIElement, in app: XCUIApplication) {
        if !element.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(waitFor(NSPredicate(format: "isHittable == true"), on: element))
        element.tap()
    }

    private func waitForLabel(_ label: String, on element: XCUIElement) -> Bool {
        waitFor(NSPredicate(format: "label == %@", label), on: element)
    }

    private func waitFor(_ predicate: NSPredicate, on element: XCUIElement) -> Bool {
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
    }
}
