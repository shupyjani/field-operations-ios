import Foundation

nonisolated enum VisitStatus: String, CaseIterable, Hashable, Sendable {
    case planned
    case enRoute
    case arrived
    case completed

    var title: String {
        switch self {
        case .planned: "Planned"
        case .enRoute: "En route"
        case .arrived: "Arrived"
        case .completed: "Completed"
        }
    }

    var symbolName: String {
        switch self {
        case .planned: "calendar"
        case .enRoute: "figure.walk"
        case .arrived: "mappin.and.ellipse"
        case .completed: "checkmark.circle.fill"
        }
    }

    var isInProgress: Bool {
        self == .enRoute || self == .arrived
    }

    /// The only status this visit may move to next. `nil` once the visit is finished.
    var successor: VisitStatus? {
        switch self {
        case .planned: .enRoute
        case .enRoute: .arrived
        case .arrived: .completed
        case .completed: nil
        }
    }

    /// Wording for the button that performs the successor transition.
    var advanceActionTitle: String? {
        switch self {
        case .planned: "Start travelling"
        case .enRoute: "Mark as arrived"
        case .arrived: "Complete visit"
        case .completed: nil
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

    func matches(_ status: VisitStatus) -> Bool {
        switch self {
        case .all: true
        case .planned: status == .planned
        case .inProgress: status.isInProgress
        case .completed: status == .completed
        }
    }
}
