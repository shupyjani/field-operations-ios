import Foundation
import Testing
@testable import AjaniFieldOperations

@Suite("Application identity")
struct AppInfoTests {
    @Test("The name shown in the app is the Ajani Mobile brand")
    func displayNameIsBrandName() {
        #expect(AppInfo.displayName == "Ajani Mobile")
    }

    /// These two names are set in different places — a Swift constant and a build
    /// setting — and have drifted apart before. The app should never introduce
    /// itself by one name while the Home Screen shows another.
    @Test("The in-app name matches the bundle display name")
    func displayNameMatchesBundle() throws {
        let bundleName = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
        let name = try #require(bundleName, "The app bundle should declare a display name")

        #expect(name == AppInfo.displayName)
    }
}
