import Foundation

/// Identifiers relied upon by the UI test target.
///
/// An identifier must sit on the view that becomes the accessibility element.
/// Placing one on a plain container makes SwiftUI push it down onto every
/// descendant, overwriting the identifiers nested inside it.
enum AccessibilityID {
    static let todayScreen = "today.screen"
    static let todayUpNextVisit = "today.upNext.visit"
    static let todayUpNextAction = "today.upNext.action"

    static let visitsEmptyState = "visits.emptyState"

    static let visitDetailPrimaryAction = "visitDetail.primaryAction"
    static let visitDetailCompletedNotice = "visitDetail.completedNotice"

    static func visitRow(_ reference: String) -> String {
        "visitRow.\(reference)"
    }
}
