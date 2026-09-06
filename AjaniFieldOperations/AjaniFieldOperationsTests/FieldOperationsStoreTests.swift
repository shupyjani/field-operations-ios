import Foundation
import Testing
@testable import AjaniFieldOperations

@Suite("Shared application state")
@MainActor
struct FieldOperationsStoreTests {
    @Test("Advancing a visit updates the shared state and the shift progress")
    func advancingVisitUpdatesState() throws {
        let store = ShiftFixtures.store(visits: [
            ShiftFixtures.visit(reference: "A", start: (8, 0), status: .planned),
            ShiftFixtures.visit(reference: "B", start: (9, 0), status: .planned)
        ])
        let visitID = try #require(store.scheduledVisits.first).id

        #expect(store.advanceStatus(of: visitID))
        #expect(store.visit(id: visitID)?.status == .enRoute)

        #expect(store.advanceStatus(of: visitID))
        #expect(store.advanceStatus(of: visitID))
        #expect(store.visit(id: visitID)?.status == .completed)
        #expect(store.progress.completed == 1)
        #expect(store.progress.remaining == 1)
    }

    @Test("A completed visit cannot be advanced again")
    func completedVisitCannotAdvance() throws {
        let store = ShiftFixtures.store(visits: [
            ShiftFixtures.visit(reference: "A", start: (8, 0), status: .completed)
        ])
        let visitID = try #require(store.visits.first).id

        #expect(!store.advanceStatus(of: visitID))
        #expect(store.visit(id: visitID)?.status == .completed)
    }

    @Test("Invalid status changes are rejected and leave state untouched")
    func rejectsInvalidStatusChange() throws {
        let store = ShiftFixtures.store(visits: [
            ShiftFixtures.visit(reference: "A", start: (8, 0), status: .planned)
        ])
        let visitID = try #require(store.visits.first).id

        #expect(!store.updateStatus(of: visitID, to: .completed))
        #expect(store.visit(id: visitID)?.status == .planned)

        #expect(store.updateStatus(of: visitID, to: .enRoute))
        #expect(store.visit(id: visitID)?.status == .enRoute)
    }

    @Test("Updating an unknown visit changes nothing")
    func ignoresUnknownVisit() {
        let store = ShiftFixtures.store(visits: [
            ShiftFixtures.visit(reference: "A", start: (8, 0), status: .planned)
        ])

        #expect(!store.advanceStatus(of: UUID()))
        #expect(!store.updateStatus(of: UUID(), to: .enRoute))
        #expect(store.visits.allSatisfy { $0.status == .planned })
    }

    @Test("The next visit follows the shared state as it changes")
    func nextVisitFollowsState() throws {
        let store = ShiftFixtures.store(visits: [
            ShiftFixtures.visit(reference: "A", start: (8, 0), status: .planned),
            ShiftFixtures.visit(reference: "B", start: (9, 0), status: .planned)
        ])
        let first = try #require(store.upNextVisit)
        #expect(first.reference == "A")

        store.updateStatus(of: first.id, to: .enRoute)
        #expect(store.upNextVisit?.reference == "A")

        store.updateStatus(of: first.id, to: .arrived)
        store.updateStatus(of: first.id, to: .completed)
        #expect(store.upNextVisit?.reference == "B")
    }

    @Test("Toggling a task updates only that task")
    func togglingTaskUpdatesSharedState() throws {
        let taskOne = ShiftFixtures.task("Prompt medication")
        let taskTwo = ShiftFixtures.task("Prepare lunch")
        let store = ShiftFixtures.store(visits: [
            ShiftFixtures.visit(reference: "A", start: (8, 0), tasks: [taskOne, taskTwo])
        ])
        let visitID = try #require(store.visits.first).id

        store.setTask(taskOne.id, isComplete: true, on: visitID)

        let visit = try #require(store.visit(id: visitID))
        #expect(visit.completedTaskCount == 1)
        #expect(visit.tasks.first { $0.id == taskOne.id }?.isComplete == true)
        #expect(visit.tasks.first { $0.id == taskTwo.id }?.isComplete == false)

        store.setTask(taskOne.id, isComplete: false, on: visitID)
        #expect(store.visit(id: visitID)?.completedTaskCount == 0)
    }

    @Test("Toggling an unknown task changes nothing")
    func ignoresUnknownTask() throws {
        let store = ShiftFixtures.store(visits: [
            ShiftFixtures.visit(reference: "A", start: (8, 0), tasks: [ShiftFixtures.task("Only task")])
        ])
        let visitID = try #require(store.visits.first).id

        store.setTask(UUID(), isComplete: true, on: visitID)

        #expect(store.visit(id: visitID)?.completedTaskCount == 0)
    }

    @Test("Hiding completed visits removes them from Today without affecting progress")
    func todayScheduleHonoursPreference() {
        let store = ShiftFixtures.store(visits: [
            ShiftFixtures.visit(reference: "A", start: (8, 0), status: .completed),
            ShiftFixtures.visit(reference: "B", start: (9, 0), status: .planned)
        ])

        #expect(store.todaySchedule.map(\.reference) == ["A", "B"])

        store.showsCompletedVisitsOnToday = false

        #expect(store.todaySchedule.map(\.reference) == ["B"])
        #expect(store.progress.total == 2)
        #expect(store.progress.completed == 1)
    }

    @Test("A shift with visits to do shows no placeholder")
    func noPlaceholderWhileWorkRemains() {
        let store = ShiftFixtures.store(visits: [
            ShiftFixtures.visit(reference: "A", start: (8, 0), status: .completed),
            ShiftFixtures.visit(reference: "B", start: (9, 0), status: .planned)
        ])

        #expect(store.upNextPlaceholder == nil)
        #expect(store.schedulePlaceholder == nil)
    }

    @Test("An empty shift is described as unscheduled, never as finished or hidden")
    func emptyShiftIsNotDescribedAsComplete() {
        let store = ShiftFixtures.store(visits: [])

        #expect(store.upNextPlaceholder == .shiftEmpty)
        #expect(store.schedulePlaceholder == .shiftEmpty)

        // The preference must not change how an empty shift is explained.
        store.showsCompletedVisitsOnToday = false
        #expect(store.schedulePlaceholder == .shiftEmpty)
    }

    @Test("A finished shift reports completion rather than an empty shift")
    func finishedShiftReportsCompletion() {
        let store = ShiftFixtures.store(visits: [
            ShiftFixtures.visit(reference: "A", start: (8, 0), status: .completed)
        ])

        #expect(store.upNextPlaceholder == .allComplete)
        #expect(store.schedulePlaceholder == nil)
    }

    @Test("Hiding completed visits on a finished shift is explained as a preference")
    func hiddenCompletedVisitsAreExplainedAsPreference() {
        let store = ShiftFixtures.store(visits: [
            ShiftFixtures.visit(reference: "A", start: (8, 0), status: .completed)
        ])

        store.showsCompletedVisitsOnToday = false

        #expect(store.todaySchedule.isEmpty)
        #expect(store.schedulePlaceholder == .completedHidden)
        // The shift is still finished, so the up-next slot keeps saying so.
        #expect(store.upNextPlaceholder == .allComplete)
    }

    @Test("Completing the last visit switches the placeholder from none to complete")
    func placeholderFollowsStateChanges() throws {
        let store = ShiftFixtures.store(visits: [
            ShiftFixtures.visit(reference: "A", start: (8, 0), status: .arrived)
        ])
        #expect(store.upNextPlaceholder == nil)

        let visitID = try #require(store.visits.first).id
        #expect(store.advanceStatus(of: visitID))

        #expect(store.upNextPlaceholder == .allComplete)
    }

    @Test("Search results are served from the shared state")
    func searchResultsUseSharedState() {
        let store = ShiftFixtures.store(visits: [
            ShiftFixtures.visit(reference: "A", clientName: "Noor Hadid", start: (8, 0), status: .planned),
            ShiftFixtures.visit(reference: "B", clientName: "Ivor Bassey", start: (9, 0), status: .completed)
        ])

        #expect(store.results(searchText: "noor", statusFilter: .all).map(\.reference) == ["A"])
        #expect(store.results(searchText: "", statusFilter: .completed).map(\.reference) == ["B"])
    }

    @Test("The demonstration shift is anchored to the injected reference date")
    func demoShiftUsesInjectedDate() throws {
        let store = ShiftFixtures.demoStore()
        let calendar = ShiftFixtures.calendar
        let day = calendar.dateComponents([.year, .month, .day], from: ShiftFixtures.referenceDate)

        #expect(store.visits.count == 7)
        #expect(store.progress.completed == 2)
        #expect(store.upNextVisit?.reference == "AV-1044")
        #expect(store.greeting == "Good morning")

        for visit in store.visits {
            let visitDay = calendar.dateComponents([.year, .month, .day], from: visit.scheduledStart)
            #expect(visitDay == day)
            #expect(visit.scheduledEnd > visit.scheduledStart)
        }

        let firstVisit = try #require(store.scheduledVisits.first)
        #expect(calendar.component(.hour, from: firstVisit.scheduledStart) == 7)
        #expect(calendar.component(.minute, from: firstVisit.scheduledStart) == 45)
    }

    @Test(
        "Greetings follow the time of day",
        arguments: [(8, "Good morning"), (13, "Good afternoon"), (19, "Good evening")]
    )
    func greetingFollowsTimeOfDay(hour: Int, expected: String) {
        let date = ShiftFixtures.time(hour, 0)

        #expect(DayGreeting.text(for: date, calendar: ShiftFixtures.calendar) == expected)
    }
}
