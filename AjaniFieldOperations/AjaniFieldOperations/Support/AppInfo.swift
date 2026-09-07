import Foundation

enum AppInfo {
    /// The name the app presents to its user. Kept in step with the bundle's
    /// display name, which is what the Home Screen shows.
    static let displayName = "Ajani Mobile"

    static var version: String {
        string(for: "CFBundleShortVersionString")
    }

    static var build: String {
        string(for: "CFBundleVersion")
    }

    private static func string(for key: String) -> String {
        Bundle.main.object(forInfoDictionaryKey: key) as? String ?? "—"
    }
}
