import Foundation

/// Why a visit was called off.
///
/// There is deliberately no "void" here. Voiding is an administrative correction
/// to a record that should never have existed, which belongs to a back office
/// rather than to a practitioner on a doorstep.
nonisolated enum CancellationReason: String, CaseIterable, Identifiable, Hashable, Sendable {
    case familyCancelled = "Family cancelled"
    case noLongerRequired = "Visit no longer required"
    case clientUnavailable = "Client unavailable"
    case officeInstruction = "Office instruction"
    case other = "Other"

    var id: String { rawValue }

    var title: String { rawValue }

    /// "Other" on its own records nothing, so it asks for the note.
    var requiresNote: Bool { self == .other }
}

nonisolated struct Cancellation: Hashable, Sendable {
    let reason: CancellationReason
    /// Trimmed when recorded; empty when no note was given.
    let note: String

    init(reason: CancellationReason, note: String = "") {
        self.reason = reason
        self.note = note
    }
}

nonisolated enum CancellationRules {
    /// Long enough for a sentence of handover, short enough to stay a note.
    static let noteLimit = 200

    /// What is wrong with a proposed cancellation, or `nil` when nothing is.
    ///
    /// Returned as a sentence so the sheet and the store cannot disagree about
    /// what counts as valid.
    static func validate(reason: CancellationReason?, note: String) -> String? {
        guard let reason else {
            return "Choose a reason for cancelling this visit."
        }

        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)

        if reason.requiresNote && trimmed.isEmpty {
            return "Add a note describing why this visit was cancelled."
        }

        if trimmed.count > noteLimit {
            return "Keep the note to \(noteLimit) characters or fewer."
        }

        return nil
    }
}
