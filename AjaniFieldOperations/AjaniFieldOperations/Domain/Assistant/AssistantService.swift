import Foundation

/// Where an answer came from, so the interface can say so honestly.
nonisolated enum AssistantSource: String, Hashable, Sendable, Codable {
    /// Computed by the deterministic assistant in this app.
    case builtIn
    /// Returned by the configured remote provider.
    case live

    var label: String {
        switch self {
        case .builtIn: AssistantCopy.builtInNotice
        case .live: AssistantCopy.liveNotice
        }
    }
}

/// One reply, and the honest account of where it came from.
nonisolated struct AssistantReply: Hashable, Sendable {
    let text: String
    let source: AssistantSource
    let kind: AssistantAnswerKind
    var selection: AssistantSelection?
}

/// What the provider is told about the round.
///
/// A copy, and a narrow one: no preferences, no navigation, no pending dialog
/// state. It is what gets posted, so it is also the limit of what could ever
/// leave the device.
nonisolated struct AssistantSnapshot: Encodable, Sendable {
    struct SnapshotTask: Encodable, Sendable {
        let id: String
        let label: String
        let done: Bool
        let hint: String?
    }

    struct SnapshotVisit: Encodable, Sendable {
        let id: String
        let reference: String
        let name: String
        let type: String
        let start: String
        let end: String
        let status: String
        let priority: Bool
        let travel: String
        let address: String
        let tasks: [SnapshotTask]
        let notes: [String]
        let tasksDone: Int
        let tasksTotal: Int
        let cancellationReason: String?
        let cancellationNote: String?
    }

    /// What this answer named, so a follow-up is read against the same set
    /// rather than widening back out to the whole round.
    ///
    /// Shaped as the browser sends it: tasks are paired with the visit they sit
    /// on, and a person is expressed as a single-visit selection rather than a
    /// field of its own. The conditions that produced the set travel with it,
    /// so a refinement narrows the question that was asked rather than the list
    /// that came back.
    struct SelectionContext: Encodable, Sendable {
        struct TimeContext: Encodable, Sendable {
            let from: Int?
            let to: Int?
            let inclusive: Bool
        }

        struct ComparatorContext: Encodable, Sendable {
            let op: String
            let n: Int
        }

        struct QueryContext: Encodable, Sendable {
            let subject: String
            let operation: String
            let statuses: [String]
            let excludedStatuses: [String]
            let actionable: Bool
            let done: Bool?
            let concepts: [String]
            let conjunction: String
            let priority: Bool?
            let photograph: Bool?
            let comparator: ComparatorContext?
            let time: TimeContext?

            init(_ query: SelectionQuery) {
                subject = query.subject.rawValue
                operation = query.operation.rawValue
                statuses = query.statuses.map(\.snapshotValue)
                excludedStatuses = query.excludedStatuses.map(\.snapshotValue)
                actionable = query.actionable
                done = query.done
                concepts = query.conceptIDs
                conjunction = query.conjunction.rawValue
                priority = query.priority
                photograph = query.photograph
                comparator = query.comparison.map {
                    ComparatorContext(op: $0.comparator.rawValue, n: $0.count)
                }
                time = query.time.map {
                    TimeContext(from: $0.from, to: $0.to, inclusive: $0.inclusive)
                }
            }
        }

        let visitIds: [String]
        let taskIds: [[String]]
        /// The conditions the set was selected by.
        let query: QueryContext?
        /// The recorded property the reader asked for.
        let property: String?
        /// The single recorded field the last answer read.
        let field: String?
    }

    let summary: String
    let completionOrder: [String]
    let visits: [SnapshotVisit]
    let selectionContext: SelectionContext?

    init(round: AssistantRound, selection: AssistantSelection? = nil) {
        summary = round.progress.summary
        completionOrder = round.completionOrder.map(\.uuidString)
        visits = round.ordered.map { visit in
            SnapshotVisit(
                id: visit.id.uuidString,
                reference: visit.reference,
                name: visit.clientName,
                type: visit.visitType,
                start: VisitFormatting.time(visit.scheduledStart),
                end: VisitFormatting.time(visit.scheduledEnd),
                status: visit.status.snapshotValue,
                priority: visit.priority == .priority,
                travel: "\(visit.location.travelMinutes) min",
                address: visit.location.singleLineAddress,
                tasks: visit.tasks.map {
                    SnapshotTask(id: $0.id.uuidString, label: $0.title, done: $0.isComplete, hint: $0.detail)
                },
                notes: visit.operationalNotes,
                tasksDone: visit.completedTaskCount,
                tasksTotal: visit.tasks.count,
                cancellationReason: visit.cancellation?.reason.title,
                cancellationNote: visit.cancellation?.note.isEmpty == false ? visit.cancellation?.note : nil
            )
        }

        selectionContext = selection.flatMap { selection -> SelectionContext? in
            guard !selection.isEmpty else { return nil }

            var visitIDs = selection.visitIDs
            if let personID = selection.personID, !visitIDs.contains(personID) {
                visitIDs.append(personID)
            }

            // A task identifier means nothing on its own, so each one travels
            // with the visit it belongs to. A task the round no longer holds is
            // dropped rather than sent as a dangling reference.
            let pairs = selection.taskIDs.compactMap { taskID -> [String]? in
                guard let visit = round.visits.first(
                    where: { $0.tasks.contains { $0.id == taskID } }
                ) else { return nil }
                return [visit.id.uuidString, taskID.uuidString]
            }

            return SelectionContext(
                visitIds: visitIDs.map(\.uuidString),
                taskIds: pairs,
                query: selection.query.map(SelectionContext.QueryContext.init),
                property: selection.property?.rawValue,
                field: selection.field?.rawValue
            )
        }
    }
}

/// One turn of the conversation as the provider is told about it.
nonisolated struct AssistantHistoryEntry: Encodable, Hashable, Sendable {
    let role: String
    let text: String
}

/// The boundary a remote provider sits behind.
///
/// Injectable so the conversation can be tested without a network, and so the
/// app can run with no provider at all.
protocol AssistantProviding: Sendable {
    /// The provider's reply, or `nil` when it is unconfigured, unreachable,
    /// slow, refused, or returned nothing usable. `nil` is not an error: the
    /// deterministic answer is the normal case rather than the degraded one.
    func reply(
        to question: String,
        history: [AssistantHistoryEntry],
        snapshot: AssistantSnapshot
    ) async -> String?
}
