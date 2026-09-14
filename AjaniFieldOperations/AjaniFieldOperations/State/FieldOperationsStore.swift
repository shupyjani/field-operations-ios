import Foundation
import Observation

/// A completion waiting on an answer.
nonisolated struct CompletionPrompt: Hashable, Sendable, Identifiable {
    enum Reason: Hashable, Sendable {
        /// Tasks remain unticked. Raised whatever the preference says.
        case outstandingTasks
        /// Nothing outstanding, but the worker asked to be checked.
        case preference
    }

    let visitID: Visit.ID
    let reason: Reason
    let outstandingCount: Int

    var id: Visit.ID { visitID }
}

/// A rejected attempt to start a second visit.
nonisolated struct BlockedTransition: Hashable, Sendable, Identifiable {
    let attemptedVisitID: Visit.ID
    let activeVisitID: Visit.ID

    var id: Visit.ID { attemptedVisitID }
}

/// Shared, in-memory application state for the current shift.
@Observable
@MainActor
final class FieldOperationsStore {
    private(set) var worker: Worker
    private(set) var shift: Shift
    private(set) var visits: [Visit]

    /// Fixed point in time the shift is presented against. Injected, alongside the
    /// calendar, so behaviour never depends on the wall clock or the device locale.
    let referenceDate: Date
    let calendar: Calendar

    // Worker preferences. Both change what the interface does.
    var showsCompletedVisitsOnToday = true
    var confirmsVisitCompletion = false

    /// The question a completion is waiting on, or `nil`.
    private(set) var pendingCompletion: CompletionPrompt?
    /// A rejected attempt to start a second visit, or `nil`.
    private(set) var blockedTransition: BlockedTransition?
    /// The visit a return-to-planned is waiting to be confirmed for, or `nil`.
    private(set) var pendingReturnID: Visit.ID?
    /// The visit a cancellation is being composed for, or `nil`.
    private(set) var pendingCancelID: Visit.ID?

    /// Bumped by every reset, so the interface can react to one having happened.
    private(set) var resetCount = 0

    init(worker: Worker, shift: Shift, visits: [Visit], referenceDate: Date, calendar: Calendar = .current) {
        self.worker = worker
        self.shift = shift
        self.visits = visits
        self.referenceDate = referenceDate
        self.calendar = calendar
    }

    convenience init(referenceDate: Date = .now, calendar: Calendar = .current) {
        self.init(
            worker: DemoFieldData.worker,
            shift: DemoFieldData.shift(on: referenceDate, calendar: calendar),
            visits: DemoFieldData.visits(on: referenceDate, calendar: calendar),
            referenceDate: referenceDate,
            calendar: calendar
        )
    }

    // MARK: - Reading the round

    var scheduledVisits: [Visit] {
        ShiftPlanner.chronological(visits)
    }

    var progress: ShiftProgress {
        ShiftPlanner.progress(for: visits)
    }

    var upNextVisit: Visit? {
        ShiftPlanner.upNext(in: visits)
    }

    /// The visit the practitioner is on, if any. At most one may hold it.
    var activeVisit: Visit? {
        ShiftPlanner.activeVisit(in: visits)
    }

    var greeting: String {
        DayGreeting.text(for: referenceDate, calendar: calendar)
    }

    /// Today's schedule, honouring the worker's completed-visit preference.
    ///
    /// Completed calls only. A cancelled visit is not a finished call, and hiding
    /// it here would quietly remove a record the practitioner may need to see.
    var todaySchedule: [Visit] {
        showsCompletedVisitsOnToday
            ? scheduledVisits
            : scheduledVisits.filter { $0.status != .completed }
    }

    /// Why the "up next" slot is empty, or `nil` when there is a visit to show.
    var upNextPlaceholder: TodayPlaceholder? {
        guard upNextVisit == nil else { return nil }
        return visits.isEmpty ? .shiftEmpty : .allComplete
    }

    /// Why the schedule list is empty, or `nil` when there are visits to list.
    var schedulePlaceholder: TodayPlaceholder? {
        guard todaySchedule.isEmpty else { return nil }
        if visits.isEmpty { return .shiftEmpty }
        return showsCompletedVisitsOnToday ? .allComplete : .completedHidden
    }

    func visit(id: Visit.ID) -> Visit? {
        visits.first { $0.id == id }
    }

    func results(searchText: String, statusFilter: VisitStatusFilter) -> [Visit] {
        VisitSearch.results(in: visits, searchText: searchText, statusFilter: statusFilter)
    }

    // MARK: - Moving a visit forward

    /// Moves a visit to `status` when the transition is valid and the round allows it.
    ///
    /// The single mutation point for a status change, so "no skipping", "no
    /// reversing" and "one active visit at a time" are enforced once rather than
    /// repeated on every button.
    @discardableResult
    func updateStatus(of id: Visit.ID, to status: VisitStatus) -> Bool {
        guard let index = visits.firstIndex(where: { $0.id == id }),
              visits[index].status.canTransition(to: status) else {
            return false
        }

        if status == .enRoute, let active = activeVisit, active.id != id {
            blockedTransition = BlockedTransition(attemptedVisitID: id, activeVisitID: active.id)
            return false
        }

        visits[index].status = status
        return true
    }

    /// Advances a visit one step, pausing for a question where one is owed.
    ///
    /// Completing is the irreversible step, so it is the one that can pause.
    /// Outstanding tasks raise that question on their own, whatever the preference
    /// says; the preference alone raises the plainer one. They are deliberately
    /// exclusive — two dialogs in a row for a single tap is worse than either.
    @discardableResult
    func advanceStatus(of id: Visit.ID, confirmed: Bool = false) -> Bool {
        guard let visit = visit(id: id), let successor = visit.status.successor else {
            return false
        }

        if successor == .completed && !confirmed {
            let outstanding = visit.outstandingTaskCount

            if outstanding > 0 {
                pendingCompletion = CompletionPrompt(
                    visitID: visit.id,
                    reason: .outstandingTasks,
                    outstandingCount: outstanding
                )
                return false
            }

            if confirmsVisitCompletion {
                pendingCompletion = CompletionPrompt(
                    visitID: visit.id,
                    reason: .preference,
                    outstandingCount: 0
                )
                return false
            }
        }

        let applied = updateStatus(of: id, to: successor)
        if applied {
            pendingCompletion = nil
        }
        return applied
    }

    /// Returns an en route visit to planned, releasing the active-visit lock.
    ///
    /// Deliberately its own action rather than a relaxation of `canTransition`,
    /// which stays strictly forward. Only en route can be undone, because only en
    /// route describes something that has not happened yet. The visit keeps its
    /// tasks and every other field; only its status moves.
    @discardableResult
    func returnToPlanned(id: Visit.ID) -> Bool {
        guard let index = visits.firstIndex(where: { $0.id == id }),
              visits[index].canReturnToPlanned else {
            return false
        }

        visits[index].status = .planned
        pendingReturnID = nil
        return true
    }

    // MARK: - Cancelling a visit

    /// Cancels a visit, recording why.
    ///
    /// Tasks are untouched — not completed, not cleared, not unticked. What was
    /// recorded before the visit was called off stays recorded. Cancelling an en
    /// route visit releases the active-visit lock as a consequence of the status
    /// changing, not as a second write.
    @discardableResult
    func cancelVisit(id: Visit.ID, reason: CancellationReason?, note: String = "") -> Bool {
        guard let index = visits.firstIndex(where: { $0.id == id }),
              visits[index].canCancel,
              let reason,
              CancellationRules.validate(reason: reason, note: note) == nil else {
            return false
        }

        visits[index].status = .cancelled
        visits[index].cancellation = Cancellation(
            reason: reason,
            note: note.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        pendingCancelID = nil
        return true
    }

    // MARK: - Tasks

    /// Records a task, when the visit allows its checklist to be edited.
    ///
    /// Refused here rather than only in the interface, so a checklist cannot be
    /// edited by any route.
    @discardableResult
    func setTask(_ taskID: VisitTask.ID, isComplete: Bool, on visitID: Visit.ID) -> Bool {
        guard let visitIndex = visits.firstIndex(where: { $0.id == visitID }),
              visits[visitIndex].canEditTasks,
              let taskIndex = visits[visitIndex].tasks.firstIndex(where: { $0.id == taskID }) else {
            return false
        }

        visits[visitIndex].tasks[taskIndex].isComplete = isComplete
        return true
    }

    // MARK: - Pending questions

    func requestReturnToPlanned(id: Visit.ID) {
        guard let visit = visit(id: id), visit.canReturnToPlanned else { return }
        pendingReturnID = id
    }

    func dismissReturnToPlanned() {
        pendingReturnID = nil
    }

    /// Refused before the sheet opens, so an unreachable status cannot be asked about.
    func requestCancellation(id: Visit.ID) {
        guard let visit = visit(id: id), visit.canCancel else { return }
        pendingCancelID = id
    }

    func dismissCancellation() {
        pendingCancelID = nil
    }

    func dismissCompletionPrompt() {
        pendingCompletion = nil
    }

    func dismissBlockedTransition() {
        blockedTransition = nil
    }

    // MARK: - Reset

    /// Restores the original round: statuses, checklists, cancellation records and
    /// preferences, with every pending question cleared.
    func reset() {
        visits = DemoFieldData.visits(on: referenceDate, calendar: calendar)
        worker = DemoFieldData.worker
        shift = DemoFieldData.shift(on: referenceDate, calendar: calendar)
        showsCompletedVisitsOnToday = true
        confirmsVisitCompletion = false
        pendingCompletion = nil
        blockedTransition = nil
        pendingReturnID = nil
        pendingCancelID = nil
        resetCount += 1
    }
}
