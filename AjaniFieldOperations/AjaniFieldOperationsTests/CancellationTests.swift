import Foundation
import Testing
@testable import AjaniFieldOperations

@Suite("Cancellation rules")
struct CancellationValidationTests {
    @Test("Offers the five approved reasons, in order")
    func offersTheApprovedReasons() {
        #expect(CancellationReason.allCases.map(\.title) == [
            "Family cancelled",
            "Visit no longer required",
            "Client unavailable",
            "Office instruction",
            "Other"
        ])
    }

    @Test("Requires a reason")
    func requiresAReason() {
        #expect(CancellationRules.validate(reason: nil, note: "") == "Choose a reason for cancelling this visit.")
        #expect(CancellationRules.validate(reason: nil, note: "Road closed") == "Choose a reason for cancelling this visit.")
    }

    @Test("Accepts any listed reason with no note, except Other")
    func acceptsListedReasonsWithoutANote() {
        for reason in CancellationReason.allCases where reason != .other {
            #expect(CancellationRules.validate(reason: reason, note: "") == nil)
        }
    }

    @Test("Requires the note when the reason is Other")
    func requiresNoteForOther() {
        let expected = "Add a note describing why this visit was cancelled."
        #expect(CancellationRules.validate(reason: .other, note: "") == expected)
        // Whitespace is not a note.
        #expect(CancellationRules.validate(reason: .other, note: "   ") == expected)
        #expect(CancellationRules.validate(reason: .other, note: "Road closed") == nil)
    }

    @Test("Holds the note to its limit, counting the trimmed text")
    func holdsTheNoteToItsLimit() {
        let limit = CancellationRules.noteLimit
        #expect(limit == 200)

        let atLimit = String(repeating: "x", count: limit)
        let overLimit = String(repeating: "x", count: limit + 1)

        #expect(CancellationRules.validate(reason: .familyCancelled, note: atLimit) == nil)
        #expect(CancellationRules.validate(reason: .familyCancelled, note: overLimit)
                == "Keep the note to \(limit) characters or fewer.")
    }
}

@Suite("Which visits may be cancelled")
struct CancellableStatusTests {
    @Test("Planned and en route may be cancelled")
    func permitsPlannedAndEnRoute() {
        #expect(ShiftFixtures.visit(reference: "A", start: (8, 0), status: .planned).canCancel)
        #expect(ShiftFixtures.visit(reference: "A", start: (8, 0), status: .enRoute).canCancel)
    }

    @Test("Arrived, completed and cancelled may not")
    func refusesClosedAndOnSiteVisits() {
        #expect(!ShiftFixtures.visit(reference: "A", start: (8, 0), status: .arrived).canCancel)
        #expect(!ShiftFixtures.visit(reference: "A", start: (8, 0), status: .completed).canCancel)
        #expect(!ShiftFixtures.visit(reference: "A", start: (8, 0), status: .cancelled).canCancel)
    }
}

@Suite("Cancelling a visit")
@MainActor
struct CancelVisitTests {
    private func plannedStore() -> FieldOperationsStore {
        ShiftFixtures.store(visits: [
            ShiftFixtures.visit(
                reference: "A",
                start: (8, 0),
                status: .planned,
                tasks: [ShiftFixtures.task("One"), ShiftFixtures.task("Two")]
            ),
            ShiftFixtures.visit(reference: "B", start: (9, 0), status: .planned)
        ])
    }

    @Test("Records the reason and the trimmed note")
    func recordsReasonAndTrimmedNote() throws {
        let store = plannedStore()
        let id = try #require(store.visits.first).id

        #expect(store.cancelVisit(id: id, reason: .other, note: "  Road closed  "))

        let visit = try #require(store.visit(id: id))
        #expect(visit.status == .cancelled)
        #expect(visit.cancellation?.reason == .other)
        #expect(visit.cancellation?.note == "Road closed")
    }

    @Test("Does not mark the visit's tasks as completed")
    func leavesTasksAlone() throws {
        let store = plannedStore()
        let id = try #require(store.visits.first).id
        let before = try #require(store.visit(id: id)).tasks

        #expect(store.cancelVisit(id: id, reason: .familyCancelled))

        let after = try #require(store.visit(id: id))
        #expect(after.tasks == before)
        #expect(after.completedTaskCount == 0)
        #expect(after.tasks.allSatisfy { !$0.isComplete })
    }

    @Test("Leaves every other visit untouched")
    func leavesOtherVisitsUntouched() throws {
        let store = plannedStore()
        let first = try #require(store.visits.first).id
        let other = try #require(store.visits.last)

        #expect(store.cancelVisit(id: first, reason: .clientUnavailable))

        #expect(store.visit(id: other.id) == other)
    }

    @Test("An invalid cancellation changes nothing")
    func invalidCancellationChangesNothing() throws {
        let store = plannedStore()
        let id = try #require(store.visits.first).id

        #expect(!store.cancelVisit(id: id, reason: nil))
        #expect(!store.cancelVisit(id: id, reason: .other, note: "   "))
        #expect(!store.cancelVisit(id: id, reason: .familyCancelled, note: String(repeating: "x", count: 201)))

        let visit = try #require(store.visit(id: id))
        #expect(visit.status == .planned)
        #expect(visit.cancellation == nil)
    }

    @Test("An arrived visit cannot be cancelled")
    func refusesArrivedVisit() throws {
        let store = ShiftFixtures.store(visits: [
            ShiftFixtures.visit(reference: "A", start: (8, 0), status: .arrived)
        ])
        let id = try #require(store.visits.first).id

        #expect(!store.cancelVisit(id: id, reason: .familyCancelled))
        #expect(store.visit(id: id)?.status == .arrived)
    }

    @Test("A cancelled visit cannot be cancelled again")
    func refusesSecondCancellation() throws {
        let store = plannedStore()
        let id = try #require(store.visits.first).id

        #expect(store.cancelVisit(id: id, reason: .familyCancelled))
        #expect(!store.cancelVisit(id: id, reason: .officeInstruction))
        #expect(store.visit(id: id)?.cancellation?.reason == .familyCancelled)
    }

    @Test("Cancelling an en route visit releases the active lock")
    func releasesTheActiveLock() throws {
        let store = plannedStore()
        let first = try #require(store.visits.first).id
        let second = try #require(store.visits.last).id

        #expect(store.advanceStatus(of: first))
        #expect(store.activeVisit?.id == first)

        #expect(store.cancelVisit(id: first, reason: .clientUnavailable))
        #expect(store.activeVisit == nil)

        // And another visit may now start.
        #expect(store.advanceStatus(of: second))
        #expect(store.visit(id: second)?.status == .enRoute)
        #expect(store.blockedTransition == nil)
    }
}

@Suite("A cancelled visit is a dead end")
@MainActor
struct CancelledVisitTests {
    private func cancelledStore() throws -> (FieldOperationsStore, Visit.ID) {
        let store = ShiftFixtures.store(visits: [
            ShiftFixtures.visit(reference: "A", start: (8, 0), status: .planned,
                                tasks: [ShiftFixtures.task("One")])
        ])
        let id = try #require(store.visits.first).id
        #expect(store.cancelVisit(id: id, reason: .familyCancelled))
        return (store, id)
    }

    @Test("Cannot advance to any status")
    func cannotAdvance() throws {
        let (store, id) = try cancelledStore()

        #expect(!store.advanceStatus(of: id))
        for status in VisitStatus.allCases {
            #expect(!store.updateStatus(of: id, to: status))
        }
        #expect(store.visit(id: id)?.status == .cancelled)
    }

    @Test("Has no successor and offers no advance action")
    func hasNoSuccessor() {
        #expect(VisitStatus.cancelled.successor == nil)
        #expect(VisitStatus.cancelled.advanceActionTitle == nil)
        #expect(VisitStatus.cancelled.sequenceStep == nil)
    }

    @Test("Cannot become the active visit or the visit in hand")
    func isNeverActiveOrNext() throws {
        let (store, _) = try cancelledStore()

        #expect(store.activeVisit == nil)
        #expect(store.upNextVisit == nil)
    }

    @Test("Cannot be returned to planned")
    func cannotReturnToPlanned() throws {
        let (store, id) = try cancelledStore()

        #expect(store.visit(id: id)?.canReturnToPlanned == false)
        #expect(!store.returnToPlanned(id: id))
    }

    @Test("Keeps a read-only checklist with its own explanation")
    func keepsReadOnlyChecklist() throws {
        let (store, id) = try cancelledStore()
        let visit = try #require(store.visit(id: id))

        #expect(!visit.canEditTasks)
        #expect(visit.taskLockReason == "This cancelled visit's checklist is read-only.")
        #expect(!store.setTask(visit.tasks[0].id, isComplete: true, on: id))
    }

    @Test("Is matched by All alone, and by none of the three status filters")
    func isMatchedByAllAlone() throws {
        let (store, _) = try cancelledStore()

        #expect(store.results(searchText: "", statusFilter: .all).count == 1)
        #expect(store.results(searchText: "", statusFilter: .planned).isEmpty)
        #expect(store.results(searchText: "", statusFilter: .inProgress).isEmpty)
        #expect(store.results(searchText: "", statusFilter: .completed).isEmpty)
    }

    @Test("Stays findable by search")
    func staysFindableBySearch() throws {
        let (store, _) = try cancelledStore()

        #expect(store.results(searchText: "Test Client", statusFilter: .all).count == 1)
    }

    @Test("Is not hidden by the show-completed preference")
    func isNotHiddenByTheCompletedPreference() throws {
        let (store, id) = try cancelledStore()

        store.showsCompletedVisitsOnToday = false

        // A cancelled visit is not a finished call, so hiding finished calls
        // must not remove it from the schedule.
        #expect(store.todaySchedule.map(\.id) == [id])
    }
}
