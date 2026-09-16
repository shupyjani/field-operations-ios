import Foundation

/// A read-only view of the round the assistant answers from.
///
/// A copy, and a narrow one: no pending dialog state and no navigation. Taking a
/// snapshot rather than the store itself is what makes the assistant unable to
/// change anything, and what keeps its answers testable without a live app.
nonisolated struct AssistantRound: Hashable, Sendable {
    let visits: [Visit]
    let workerFirstName: String
    let shiftWindow: String
    let round: String
    /// Visit identifiers in the order they were completed this session.
    let completionOrder: [Visit.ID]
    let showsCompletedVisitsOnToday: Bool
    let confirmsVisitCompletion: Bool

    init(
        visits: [Visit],
        workerFirstName: String,
        shiftWindow: String,
        round: String,
        completionOrder: [Visit.ID] = [],
        showsCompletedVisitsOnToday: Bool = true,
        confirmsVisitCompletion: Bool = false
    ) {
        self.visits = visits
        self.workerFirstName = workerFirstName
        self.shiftWindow = shiftWindow
        self.round = round
        self.completionOrder = completionOrder
        self.showsCompletedVisitsOnToday = showsCompletedVisitsOnToday
        self.confirmsVisitCompletion = confirmsVisitCompletion
    }

    var ordered: [Visit] { AssistantQueries.allVisits(visits) }

    var active: Visit? { ShiftPlanner.activeVisit(in: visits) }

    var upNext: Visit? { ShiftPlanner.upNext(in: visits) }

    var progress: ShiftProgress { ShiftPlanner.progress(for: visits) }

    func visit(id: Visit.ID) -> Visit? { visits.first { $0.id == id } }

    /// The visits completed during this session, oldest completion first.
    var sessionCompletions: [Visit] {
        completionOrder.compactMap { id in
            guard let visit = visit(id: id), visit.status == .completed else { return nil }
            return visit
        }
    }
}

/// What an answer named, so a follow-up has a referent.
nonisolated struct AssistantSelection: Hashable, Sendable {
    var visitIDs: [Visit.ID] = []
    var taskIDs: [VisitTask.ID] = []
    var personID: Visit.ID?
    /// What the last answer was about, so a correction can re-ask the same
    /// question about a different person rather than guessing a new subject.
    var lastKind: AssistantAnswerKind?

    /// The conditions that produced this set, kept so a refinement can be
    /// re-run against the round as it now stands rather than replaying a list
    /// that may since have gone stale.
    var query: SelectionQuery?

    /// The recorded property the reader asked for, preserved across a
    /// refinement so "Ivor" after "how long is the walking task?" still
    /// answers about duration.
    var property: TaskProperty?

    /// A single recorded field the last answer read, so "was there an
    /// additional note?" knows which kind of note is under discussion.
    var field: Field?

    /// What the assistant asked for and has not yet been given.
    var pending: TaskProperty?

    /// The question asked before this one, so "what did I just ask?" can be
    /// answered from the exchange rather than from anything else.
    var previousQuestion: String?

    /// A recorded field a follow-up can return to.
    enum Field: String, Hashable, Sendable {
        case cancellation
        case operationalNote
        case travel
    }

    var isEmpty: Bool {
        visitIDs.isEmpty && taskIDs.isEmpty && personID == nil
            && query == nil && field == nil && pending == nil
    }

    /// Whether the last answer was about checklists.
    var wasAboutTasks: Bool {
        guard let lastKind else { return false }
        return [.tasks, .taskCount, .taskSearch, .taskDetail, .taskTotals].contains(lastKind)
    }
}

/// The family an answer belongs to. Used by tests and by follow-up handling
/// rather than shown to the reader.
nonisolated enum AssistantAnswerKind: String, Hashable, Sendable {
    case active, next, counts, remaining, statusList, priority, person, notFound
    case ambiguous, tasks, taskCount, taskSearch, taskDetail, taskTotals
    case notes, schedule, travel, duration, completion, cancellation
    case concept, contact, similar, compound, selection
    case guidance, absentControl, mutation, clinical, disclosure, demographic
    case clarify, unsupported
}

nonisolated struct LocalAnswer: Hashable, Sendable {
    let text: String
    let kind: AssistantAnswerKind
    var selection: AssistantSelection?

    /// Boundary answers are decided locally and never sent to a provider.
    var isBoundary: Bool {
        kind == .clinical || kind == .disclosure || kind == .mutation
    }
}
