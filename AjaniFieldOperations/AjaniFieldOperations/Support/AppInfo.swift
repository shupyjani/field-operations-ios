import Foundation

enum AppInfo {
    static let displayName = "Ajani Field Operations"

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
