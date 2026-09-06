import XCTest

final class FieldOperationsLaunchTests: XCTestCase {
    override class var runsForEachTargetApplicationUIConfiguration: Bool {
        false
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testLaunchReachesTheTodayDashboard() throws {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(app.scrollViews["today.screen"].waitForExistence(timeout: 20))

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Today"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
