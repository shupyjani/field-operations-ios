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
    /// Present only once the visit has been cancelled.
    var cancellation: Cancellation?

    init(
        id: UUID,
        reference: String,
        clientName: String,
        visitType: String,
        location: VisitLocation,
        scheduledStart: Date,
        scheduledEnd: Date,
        priority: VisitPriority,
        operationalNotes: [String],
        tasks: [VisitTask],
        status: VisitStatus,
        cancellation: Cancellation? = nil
    ) {
        self.id = id
        self.reference = reference
        self.clientName = clientName
        self.visitType = visitType
        self.location = location
        self.scheduledStart = scheduledStart
        self.scheduledEnd = scheduledEnd
        self.priority = priority
        self.operationalNotes = operationalNotes
        self.tasks = tasks
        self.status = status
        self.cancellation = cancellation
    }

    var scheduledDuration: TimeInterval {
        scheduledEnd.timeIntervalSince(scheduledStart)
    }

    var scheduledDurationMinutes: Int {
        Int((scheduledDuration / 60).rounded())
    }

    var completedTaskCount: Int {
        tasks.count { $0.isComplete }
    }

    var outstandingTaskCount: Int {
        tasks.count { !$0.isComplete }
    }

    /// Whether this visit's checklist may be edited.
    ///
    /// Arrived only. Ticking a task on a planned or en route visit would record
    /// work that cannot have happened yet, and a completed or cancelled visit is
    /// a closed record. Every other status keeps the checklist readable.
    var canEditTasks: Bool {
        status == .arrived
    }

    /// Why the checklist is read-only, or `nil` when it is not.
    ///
    /// The sentence lives beside the rule so the interface cannot explain a
    /// restriction differently from the way it is enforced.
    var taskLockReason: String? {
        guard !canEditTasks else { return nil }
        switch status {
        case .completed: return "This completed visit's checklist is read-only."
        case .cancelled: return "This cancelled visit's checklist is read-only."
        default: return "Task completion becomes available after arrival."
        }
    }

    /// Planned and en route only. Arrived means the practitioner is already at the
    /// address, and completed and cancelled visits are closed records.
    var canCancel: Bool {
        status == .planned || status == .enRoute
    }

    /// The one step that may be undone: a practitioner redirected before arrival.
    var canReturnToPlanned: Bool {
        status == .enRoute
    }
}
