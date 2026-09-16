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
    static let visitDetailCancelledNotice = "visitDetail.cancelledNotice"
    static let visitDetailCancelAction = "visitDetail.cancelAction"
    static let visitDetailReturnAction = "visitDetail.returnAction"
    static let visitDetailTaskLock = "visitDetail.taskLock"
    static let visitDetailCancellationReason = "visitDetail.cancellationReason"

    static let cancelSheetNote = "cancelSheet.note"
    static let cancelSheetConfirm = "cancelSheet.confirm"
    static let cancelSheetRequirement = "cancelSheet.requirement"

    static let completionConfirm = "completion.confirm"
    static let returnConfirm = "return.confirm"

    static let moreResetAction = "more.resetAction"
    static let moreResetConfirm = "more.resetConfirm"
    static let moreAssistantAction = "more.assistantAction"

    static let assistantScreen = "assistant.screen"
    static let assistantWelcome = "assistant.welcome"
    static let assistantInput = "assistant.input"
    static let assistantSend = "assistant.send"
    static let assistantStatus = "assistant.status"
    static let assistantReply = "assistant.reply"
    static let assistantUserMessage = "assistant.userMessage"
    static let assistantReplySource = "assistant.replySource"
    static let assistantClearAction = "assistant.clearAction"
    static let assistantClearConfirm = "assistant.clearConfirm"

    static func assistantSuggestion(_ question: String) -> String {
        "assistant.suggestion.\(question)"
    }

    static func visitRow(_ reference: String) -> String {
        "visitRow.\(reference)"
    }

    static func visitTask(_ title: String) -> String {
        "visitTask.\(title)"
    }

    static func cancelReason(_ reason: CancellationReason) -> String {
        "cancelSheet.reason.\(reason.rawValue)"
    }
}
