import UIKit
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
        static let completionConfirm = "completion.confirm"

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

    func testVisitsShowsItsNavigationTitle() throws {
        let app = launchApp()
        openVisits(in: app)

        // Scoped to the navigation bar so this can never be satisfied by the
        // "Visits" tab button, which lives in the tab bar.
        let navigationBar = app.navigationBars["Visits"]
        XCTAssertTrue(navigationBar.waitForExistence(timeout: timeout))

        let title = navigationBar.staticTexts["Visits"]
        XCTAssertTrue(title.waitForExistence(timeout: timeout), "The Visits screen should show a navigation title")
        XCTAssertFalse(title.frame.isEmpty, "The Visits title should occupy layout space")

        // The title sits above the search field, as on Today and More.
        let searchField = navigationBar.searchFields.firstMatch
        XCTAssertTrue(searchField.waitForExistence(timeout: timeout))
        XCTAssertLessThan(title.frame.maxY, searchField.frame.minY)

        // Existence is not enough: when this bug was live the title element was
        // present, correctly framed and hittable, yet nothing was drawn. Only the
        // rendered pixels distinguish the two, in either colour scheme.
        let titleRegion = title.frame.offsetBy(
            dx: -navigationBar.frame.minX,
            dy: -navigationBar.frame.minY
        )
        XCTAssertGreaterThan(
            contrast(in: navigationBar.screenshot(), region: titleRegion),
            60,
            "The Visits title occupies layout space but is not drawn"
        )

        // Still correct after leaving and returning to the tab.
        app.tabBars.buttons["Today"].tap()
        XCTAssertTrue(app.buttons[ID.upNextVisit].waitForExistence(timeout: timeout))
        openVisits(in: app)
        XCTAssertTrue(app.navigationBars["Visits"].staticTexts["Visits"].waitForExistence(timeout: timeout))
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
            app.staticTexts["Daughter usually calls around nine; happy to be interrupted."]
                .waitForExistence(timeout: timeout)
        )
        XCTAssertTrue(app.staticTexts["Desmond Achebe"].exists)
        // A finished visit offers no further action.
        XCTAssertTrue(app.staticTexts[ID.visitDetailCompletedNotice].exists)
        XCTAssertFalse(app.buttons[ID.visitDetailPrimaryAction].exists)
    }

    func testCompletingAVisitStatusJourney() throws {
        let app = launchApp()
        // The round opens with a visit already on site, and only one visit may be
        // active, so that one is closed before another journey can begin.
        releaseTheActiveVisit(in: app)

        openVisits(in: app)

        let plannedFilter = app.buttons["Planned"]
        XCTAssertTrue(plannedFilter.waitForExistence(timeout: timeout))
        plannedFilter.tap()

        let row = app.buttons[ID.visitRow("AV-1044")]
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
        // Every task is still outstanding, so completing asks before it closes.
        confirmOutstandingCompletion(in: app)

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
        confirmOutstandingCompletion(in: app)

        // Once complete, the card moves on to the next planned visit.
        XCTAssertTrue(waitForLabel("Start travelling", on: app.buttons[ID.upNextAction]))

        let upNext = app.buttons[ID.upNextVisit]
        XCTAssertTrue(upNext.waitForExistence(timeout: timeout))
        XCTAssertTrue(
            upNext.label.contains("Ivor Bankole"),
            "Up next should advance to the next planned visit, but showed: \(upNext.label)"
        )
    }

    func testSearchNarrowsTheVisitsList() throws {
        let app = launchApp()
        openVisits(in: app)

        search(for: "Halina", in: app)

        // The result summary is the only signal that filtering has actually been
        // applied: the matching row is already on screen before the search runs,
        // so waiting on it would prove nothing and leave the negative assertion
        // below racing the filter.
        XCTAssertTrue(app.staticTexts["Showing 1 of 7 visits"].waitForExistence(timeout: timeout))
        XCTAssertTrue(app.buttons[ID.visitRow("AV-1045")].exists)
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

    /// Answers the outstanding-task question that stands between an arrived visit
    /// with unticked work and being closed.
    private func confirmOutstandingCompletion(in app: XCUIApplication) {
        let confirm = app.alerts.buttons[ID.completionConfirm].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: timeout), "Completing with tasks outstanding should ask first")
        confirm.tap()
    }

    /// Closes the visit the round opens on, so another may be started.
    private func releaseTheActiveVisit(in app: XCUIApplication) {
        let action = app.buttons[ID.upNextAction]
        XCTAssertTrue(action.waitForExistence(timeout: timeout))
        XCTAssertEqual(action.label, "Complete visit")

        tap(action, in: app)
        confirmOutstandingCompletion(in: app)

        XCTAssertTrue(waitForLabel("Start travelling", on: app.buttons[ID.upNextAction]))
    }

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

    /// Difference between the lightest and darkest pixel in a region, 0–255.
    /// A region containing drawn text has a wide spread; flat background is near zero.
    private func contrast(in screenshot: XCUIScreenshot, region: CGRect) -> Int {
        let image = screenshot.image
        let scale = image.scale
        let scaled = CGRect(
            x: region.origin.x * scale,
            y: region.origin.y * scale,
            width: region.width * scale,
            height: region.height * scale
        )
        guard let cropped = image.cgImage?.cropping(to: scaled),
              cropped.width > 0, cropped.height > 0 else {
            return 0
        }

        let width = cropped.width
        let height = cropped.height
        var pixels = [UInt8](repeating: 0, count: width * height)
        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else {
            return 0
        }
        context.draw(cropped, in: CGRect(x: 0, y: 0, width: width, height: height))

        guard let darkest = pixels.min(), let lightest = pixels.max() else { return 0 }
        return Int(lightest) - Int(darkest)
    }

    private func waitForLabel(_ label: String, on element: XCUIElement) -> Bool {
        waitFor(NSPredicate(format: "label == %@", label), on: element)
    }

    private func waitFor(_ predicate: NSPredicate, on element: XCUIElement) -> Bool {
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
    }
}
