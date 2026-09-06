import Foundation

nonisolated struct VisitLocation: Hashable, Sendable {
    let addressLine: String
    let district: String
    let postcode: String
    /// Estimated travel time from the preceding visit, in minutes.
    let travelMinutes: Int

    var singleLineAddress: String {
        "\(addressLine), \(district) \(postcode)"
    }
}

nonisolated struct VisitTask: Identifiable, Hashable, Sendable {
    let id: UUID
    let title: String
    let detail: String?
    var isComplete: Bool

    init(id: UUID, title: String, detail: String? = nil, isComplete: Bool = false) {
        self.id = id
        self.title = title
        self.detail = detail
        self.isComplete = isComplete
    }
}

nonisolated enum VisitPriority: String, Hashable, Sendable {
    case standard
    case priority

    var title: String? {
        switch self {
        case .standard: nil
        case .priority: "Priority"
        }
    }
}

nonisolated struct Visit: Identifiable, Hashable, Sendable {
    let id: UUID
    let reference: String
    let clientName: String
    let visitType: String
    let location: VisitLocation
    let scheduledStart: Date
    let scheduledEnd: Date
    let priority: VisitPriority
    let operationalNotes: [String]
    var tasks: [VisitTask]
    var status: VisitStatus

    var scheduledDuration: TimeInterval {
        scheduledEnd.timeIntervalSince(scheduledStart)
    }

    var scheduledDurationMinutes: Int {
        Int((scheduledDuration / 60).rounded())
    }

    var completedTaskCount: Int {
        tasks.count { $0.isComplete }
    }
}
