import Foundation

nonisolated enum VisitStatus: String, CaseIterable, Hashable, Sendable {
    case planned
    case enRoute
    case arrived
    case completed
    case cancelled

    /// The forward sequence a visit travels. Cancelled sits outside it on purpose:
    /// it is not a further step but an exit, so every rule built on this order
    /// refuses a cancelled visit without having to name it.
    static let sequence: [VisitStatus] = [.planned, .enRoute, .arrived, .completed]

    var title: String {
        switch self {
        case .planned: "Planned"
        case .enRoute: "En route"
        case .arrived: "Arrived"
        case .completed: "Completed"
        case .cancelled: "Cancelled"
        }
    }

    var symbolName: String {
        switch self {
        case .planned: "calendar"
        case .enRoute: "figure.walk"
        case .arrived: "mappin.and.ellipse"
        case .completed: "checkmark.circle.fill"
        case .cancelled: "xmark.circle.fill"
        }
    }

    var isInProgress: Bool {
        self == .enRoute || self == .arrived
    }

    /// Nothing further will happen at this address.
    var isResolved: Bool {
        self == .completed || self == .cancelled
    }

    /// Position in the forward sequence, or `nil` for a status outside it.
    var sequenceStep: Int? {
        Self.sequence.firstIndex(of: self).map { $0 + 1 }
    }

    /// The only status this visit may move to next. `nil` once it has left the sequence.
    var successor: VisitStatus? {
        guard let index = Self.sequence.firstIndex(of: self),
              index < Self.sequence.count - 1 else {
            return nil
        }
        return Self.sequence[index + 1]
    }

    /// Wording for the button that performs the successor transition.
    var advanceActionTitle: String? {
        switch self {
        case .planned: "Start travelling"
        case .enRoute: "Mark as arrived"
        case .arrived: "Complete visit"
        case .completed, .cancelled: nil
        }
    }

    func canTransition(to status: VisitStatus) -> Bool {
        successor == status
    }
}

/// Status grouping offered on the Visits screen.
nonisolated enum VisitStatusFilter: String, CaseIterable, Identifiable, Hashable, Sendable {
    case all
    case planned
    case inProgress
    case completed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "All"
        case .planned: "Planned"
        case .inProgress: "In progress"
        case .completed: "Completed"
        }
    }

    /// A cancelled visit is matched by `all` alone: it is neither planned, nor in
    /// progress, nor completed, and folding it into any of those would misreport it.
    func matches(_ status: VisitStatus) -> Bool {
        switch self {
        case .all: true
        case .planned: status == .planned
        case .inProgress: status.isInProgress
        case .completed: status == .completed
        }
    }
}
