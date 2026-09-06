import Foundation
import Observation

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

    var scheduledVisits: [Visit] {
        ShiftPlanner.chronological(visits)
    }

    var progress: ShiftProgress {
        ShiftPlanner.progress(for: visits)
    }

    var upNextVisit: Visit? {
        ShiftPlanner.upNext(in: visits)
    }

    var greeting: String {
        DayGreeting.text(for: referenceDate, calendar: calendar)
    }

    /// Today's schedule, honouring the worker's completed-visit preference.
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

    /// Moves a visit to `status` when the transition is valid. Returns whether it applied.
    @discardableResult
    func updateStatus(of id: Visit.ID, to status: VisitStatus) -> Bool {
        guard let index = visits.firstIndex(where: { $0.id == id }),
              visits[index].status.canTransition(to: status) else {
            return false
        }
        visits[index].status = status
        return true
    }

    /// Advances a visit to the next status in the journey. Returns whether it applied.
    @discardableResult
    func advanceStatus(of id: Visit.ID) -> Bool {
        guard let visit = visit(id: id), let successor = visit.status.successor else {
            return false
        }
        return updateStatus(of: id, to: successor)
    }

    func setTask(_ taskID: VisitTask.ID, isComplete: Bool, on visitID: Visit.ID) {
        guard let visitIndex = visits.firstIndex(where: { $0.id == visitID }),
              let taskIndex = visits[visitIndex].tasks.firstIndex(where: { $0.id == taskID }) else {
            return
        }
        visits[visitIndex].tasks[taskIndex].isComplete = isComplete
    }
}
