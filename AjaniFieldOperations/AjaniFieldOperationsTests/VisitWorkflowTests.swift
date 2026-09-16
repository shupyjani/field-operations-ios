import Foundation
import Testing
@testable import AjaniFieldOperations

@Suite("One active visit at a time")
@MainActor
struct ActiveVisitTests {
    private func twoPlanned() -> FieldOperationsStore {
        ShiftFixtures.store(visits: [
            ShiftFixtures.visit(reference: "A", clientName: "Alice Adeyemi", start: (8, 0), status: .planned),
            ShiftFixtures.visit(reference: "B", clientName: "Bola Bankole", start: (9, 0), status: .planned)
        ])
    }

    @Test("A second visit cannot be started while one is active")
    func rejectsASecondActiveVisit() throws {
        let store = twoPlanned()
        let first = try #require(store.visits.first).id
        let second = try #require(store.visits.last).id

        #expect(store.advanceStatus(of: first))
        #expect(!store.advanceStatus(of: second))

        // Neither visit moved, and the block names both sides.
        #expect(store.visit(id: first)?.status == .enRoute)
        #expect(store.visit(id: second)?.status == .planned)
        #expect(store.blockedTransition?.activeVisitID == first)
        #expect(store.blockedTransition?.attemptedVisitID == second)
    }

    @Test("The block applies when the active visit has arrived, not only en route")
    func rejectsWhileArrived() throws {
        let store = twoPlanned()
        let first = try #require(store.visits.first).id
        let second = try #require(store.visits.last).id

        #expect(store.advanceStatus(of: first))
        #expect(store.advanceStatus(of: first))
        #expect(store.visit(id: first)?.status == .arrived)

        #expect(!store.advanceStatus(of: second))
        #expect(store.visit(id: second)?.status == .planned)
    }

    @Test("The active visit finishes its own sequence unhindered")
    func activeVisitAdvancesFreely() throws {
        let store = twoPlanned()
        let first = try #require(store.visits.first).id

        #expect(store.advanceStatus(of: first))
        #expect(store.advanceStatus(of: first))
        #expect(store.advanceStatus(of: first))

        #expect(store.visit(id: first)?.status == .completed)
        #expect(store.activeVisit == nil)
    }

    @Test("Completing the active visit releases the next one")
    func completingReleasesTheLock() throws {
        let store = twoPlanned()
        let first = try #require(store.visits.first).id
        let second = try #require(store.visits.last).id

        for _ in 0..<3 { store.advanceStatus(of: first) }
        #expect(store.activeVisit == nil)

        #expect(store.advanceStatus(of: second))
        #expect(store.activeVisit?.id == second)
    }

    @Test("Dismissing the block leaves both visits alone")
    func dismissingTheBlockChangesNothing() throws {
        let store = twoPlanned()
        let first = try #require(store.visits.first).id
        let second = try #require(store.visits.last).id

        store.advanceStatus(of: first)
        store.advanceStatus(of: second)
        #expect(store.blockedTransition != nil)

        store.dismissBlockedTransition()

        #expect(store.blockedTransition == nil)
        #expect(store.visit(id: first)?.status == .enRoute)
        #expect(store.visit(id: second)?.status == .planned)
    }
}

@Suite("En route may be returned to planned")
@MainActor
struct ReturnToPlannedTests {
    @Test("Only an en route visit accepts the action")
    func onlyEnRouteAccepts() {
        #expect(ShiftFixtures.visit(reference: "A", start: (8, 0), status: .enRoute).canReturnToPlanned)
        #expect(!ShiftFixtures.visit(reference: "A", start: (8, 0), status: .planned).canReturnToPlanned)
        #expect(!ShiftFixtures.visit(reference: "A", start: (8, 0), status: .arrived).canReturnToPlanned)
        #expect(!ShiftFixtures.visit(reference: "A", start: (8, 0), status: .completed).canReturnToPlanned)
        #expect(!ShiftFixtures.visit(reference: "A", start: (8, 0), status: .cancelled).canReturnToPlanned)
    }

    @Test("Moves the status back and nothing else about the visit")
    func movesOnlyTheStatus() throws {
        let store = ShiftFixtures.store(visits: [
            ShiftFixtures.visit(reference: "A", start: (8, 0), status: .planned,
                                tasks: [ShiftFixtures.task("One"), ShiftFixtures.task("Two")])
        ])
        let id = try #require(store.visits.first).id
        store.advanceStatus(of: id)
        let before = try #require(store.visit(id: id))

        #expect(store.returnToPlanned(id: id))

        let after = try #require(store.visit(id: id))
        #expect(after.status == .planned)
        #expect(after.tasks == before.tasks)
        #expect(after.reference == before.reference)
        #expect(after.cancellation == nil)
    }

    @Test("Releases the active lock so another visit may start")
    func releasesTheActiveLock() throws {
        let store = ShiftFixtures.store(visits: [
            ShiftFixtures.visit(reference: "A", start: (8, 0), status: .planned),
            ShiftFixtures.visit(reference: "B", start: (9, 0), status: .planned)
        ])
        let first = try #require(store.visits.first).id
        let second = try #require(store.visits.last).id

        store.advanceStatus(of: first)
        #expect(store.activeVisit?.id == first)

        #expect(store.returnToPlanned(id: first))
        #expect(store.activeVisit == nil)

        #expect(store.advanceStatus(of: second))
        #expect(store.activeVisit?.id == second)
    }

    @Test("Refuses arrived, completed, planned and cancelled outright")
    func refusesEveryOtherStatus() throws {
        for status in [VisitStatus.planned, .arrived, .completed, .cancelled] {
            let store = ShiftFixtures.store(visits: [
                ShiftFixtures.visit(reference: "A", start: (8, 0), status: status)
            ])
            let id = try #require(store.visits.first).id

            #expect(!store.returnToPlanned(id: id))
            #expect(store.visit(id: id)?.status == status)
        }
    }

    @Test("Does not loosen the forward rule beside it")
    func doesNotLoosenTheForwardRule() throws {
        let store = ShiftFixtures.store(visits: [
            ShiftFixtures.visit(reference: "A", start: (8, 0), status: .arrived)
        ])
        let id = try #require(store.visits.first).id

        #expect(!store.updateStatus(of: id, to: .planned))
        #expect(!store.updateStatus(of: id, to: .enRoute))
        #expect(store.visit(id: id)?.status == .arrived)
    }
}

@Suite("Tasks may only be recorded on arrival")
@MainActor
struct TaskEditingTests {
    private func store(status: VisitStatus) -> FieldOperationsStore {
        ShiftFixtures.store(visits: [
            ShiftFixtures.visit(reference: "A", start: (8, 0), status: status,
                                tasks: [ShiftFixtures.task("One"), ShiftFixtures.task("Two")])
        ])
    }

    @Test("Editing is permitted for an arrived visit only")
    func permitsArrivedOnly() {
        #expect(ShiftFixtures.visit(reference: "A", start: (8, 0), status: .arrived).canEditTasks)
        #expect(!ShiftFixtures.visit(reference: "A", start: (8, 0), status: .planned).canEditTasks)
        #expect(!ShiftFixtures.visit(reference: "A", start: (8, 0), status: .enRoute).canEditTasks)
        #expect(!ShiftFixtures.visit(reference: "A", start: (8, 0), status: .completed).canEditTasks)
        #expect(!ShiftFixtures.visit(reference: "A", start: (8, 0), status: .cancelled).canEditTasks)
    }

    @Test(
        "A locked checklist refuses the write",
        arguments: [VisitStatus.planned, .enRoute, .completed, .cancelled]
    )
    func refusesWriteWhenLocked(status: VisitStatus) throws {
        let store = store(status: status)
        let visit = try #require(store.visits.first)

        #expect(!store.setTask(visit.tasks[0].id, isComplete: true, on: visit.id))
        #expect(store.visit(id: visit.id)?.completedTaskCount == 0)
    }

    @Test("An arrived visit records the task")
    func recordsWhenArrived() throws {
        let store = store(status: .arrived)
        let visit = try #require(store.visits.first)

        #expect(store.setTask(visit.tasks[0].id, isComplete: true, on: visit.id))
        #expect(store.visit(id: visit.id)?.completedTaskCount == 1)
    }

    @Test("The lock explains itself in the words the interface uses")
    func explainsTheLock() {
        #expect(ShiftFixtures.visit(reference: "A", start: (8, 0), status: .arrived).taskLockReason == nil)
        #expect(ShiftFixtures.visit(reference: "A", start: (8, 0), status: .planned).taskLockReason
                == "Task completion becomes available after arrival.")
        #expect(ShiftFixtures.visit(reference: "A", start: (8, 0), status: .enRoute).taskLockReason
                == "Task completion becomes available after arrival.")
        #expect(ShiftFixtures.visit(reference: "A", start: (8, 0), status: .completed).taskLockReason
                == "This completed visit's checklist is read-only.")
        #expect(ShiftFixtures.visit(reference: "A", start: (8, 0), status: .cancelled).taskLockReason
                == "This cancelled visit's checklist is read-only.")
    }

    @Test("Ticks recorded on arrival survive completion")
    func ticksSurviveCompletion() throws {
        let store = store(status: .arrived)
        let visit = try #require(store.visits.first)

        #expect(store.setTask(visit.tasks[0].id, isComplete: true, on: visit.id))
        store.advanceStatus(of: visit.id, confirmed: true)

        #expect(store.visit(id: visit.id)?.status == .completed)
        #expect(store.visit(id: visit.id)?.completedTaskCount == 1)
    }

    @Test("Returning to planned does not clear task information")
    func returningPreservesTasks() throws {
        let store = store(status: .planned)
        let id = try #require(store.visits.first).id
        store.advanceStatus(of: id)
        let before = try #require(store.visit(id: id)).tasks

        #expect(store.returnToPlanned(id: id))

        #expect(store.visit(id: id)?.tasks == before)
    }
}

@Suite("Completion safeguards")
@MainActor
struct CompletionSafeguardTests {
    private func arrivedStore(doneCount: Int) -> FieldOperationsStore {
        let tasks = (0..<3).map { index in
            ShiftFixtures.task("Task \(index)", isComplete: index < doneCount)
        }
        return ShiftFixtures.store(visits: [
            ShiftFixtures.visit(reference: "A", start: (8, 0), status: .arrived, tasks: tasks)
        ])
    }

    @Test("Outstanding tasks raise a warning and change nothing")
    func outstandingTasksRaiseAWarning() throws {
        let store = arrivedStore(doneCount: 1)
        let id = try #require(store.visits.first).id

        #expect(!store.advanceStatus(of: id))

        #expect(store.visit(id: id)?.status == .arrived)
        #expect(store.pendingCompletion?.reason == .outstandingTasks)
        #expect(store.pendingCompletion?.outstandingCount == 2)
    }

    @Test("The warning counts down as tasks are ticked")
    func warningCountsDown() throws {
        let store = arrivedStore(doneCount: 2)
        let visit = try #require(store.visits.first)

        #expect(!store.advanceStatus(of: visit.id))
        #expect(store.pendingCompletion?.outstandingCount == 1)
    }

    @Test("Accepting the warning completes the visit")
    func acceptingTheWarningCompletes() throws {
        let store = arrivedStore(doneCount: 1)
        let id = try #require(store.visits.first).id

        store.advanceStatus(of: id)
        #expect(store.advanceStatus(of: id, confirmed: true))

        #expect(store.visit(id: id)?.status == .completed)
        #expect(store.pendingCompletion == nil)
        // Accepting does not tick the outstanding tasks.
        #expect(store.visit(id: id)?.completedTaskCount == 1)
    }

    @Test("Dismissing the warning leaves the visit alone")
    func dismissingTheWarningChangesNothing() throws {
        let store = arrivedStore(doneCount: 1)
        let id = try #require(store.visits.first).id

        store.advanceStatus(of: id)
        store.dismissCompletionPrompt()

        #expect(store.pendingCompletion == nil)
        #expect(store.visit(id: id)?.status == .arrived)
    }

    @Test("With every task ticked, the preference raises the plainer question")
    func preferenceRaisesThePlainQuestion() throws {
        let store = arrivedStore(doneCount: 3)
        store.confirmsVisitCompletion = true
        let id = try #require(store.visits.first).id

        #expect(!store.advanceStatus(of: id))

        #expect(store.pendingCompletion?.reason == .preference)
        #expect(store.pendingCompletion?.outstandingCount == 0)
        #expect(store.visit(id: id)?.status == .arrived)
    }

    @Test("Outstanding tasks win over the preference, so only one question is asked")
    func outstandingTasksTakePrecedence() throws {
        let store = arrivedStore(doneCount: 1)
        store.confirmsVisitCompletion = true
        let id = try #require(store.visits.first).id

        #expect(!store.advanceStatus(of: id))
        #expect(store.pendingCompletion?.reason == .outstandingTasks)

        // Confirming answers both at once: there is no second question.
        #expect(store.advanceStatus(of: id, confirmed: true))
        #expect(store.pendingCompletion == nil)
        #expect(store.visit(id: id)?.status == .completed)
    }

    @Test("With every task ticked and the preference off, completing is immediate")
    func completesImmediately() throws {
        let store = arrivedStore(doneCount: 3)
        let id = try #require(store.visits.first).id

        #expect(store.advanceStatus(of: id))

        #expect(store.visit(id: id)?.status == .completed)
        #expect(store.pendingCompletion == nil)
    }

    @Test("Nothing is confirmed before the earlier steps")
    func earlierStepsAreNeverConfirmed() throws {
        let store = ShiftFixtures.store(visits: [
            ShiftFixtures.visit(reference: "A", start: (8, 0), status: .planned,
                                tasks: [ShiftFixtures.task("One")])
        ])
        store.confirmsVisitCompletion = true
        let id = try #require(store.visits.first).id

        #expect(store.advanceStatus(of: id))
        #expect(store.pendingCompletion == nil)
        #expect(store.advanceStatus(of: id))
        #expect(store.pendingCompletion == nil)
        #expect(store.visit(id: id)?.status == .arrived)
    }
}

@Suite("Progress counts completed and cancelled apart")
@MainActor
struct ProgressParityTests {
    @Test("Reads exactly as before when nothing is cancelled")
    func readsAsBeforeWithoutCancellations() {
        let store = ShiftFixtures.demoStore()

        #expect(store.progress.percentage == 29)
        #expect(store.progress.summary == "2 of 7 visits complete · 5 remaining")
    }

    @Test("A cancellation does not raise the completed count")
    func cancellationDoesNotRaiseCompleted() throws {
        let store = ShiftFixtures.demoStore()
        let planned = try #require(store.visits.first { $0.status == .planned })

        #expect(store.cancelVisit(id: planned.id, reason: .familyCancelled))

        let progress = store.progress
        #expect(progress.completed == 2)
        #expect(progress.cancelled == 1)
        #expect(progress.resolved == 3)
        #expect(progress.remaining == 4)
        #expect(progress.percentage == 43)
    }

    @Test("Both outcomes are spelled out once there is a cancellation")
    func spellsBothOutcomesOut() throws {
        let store = ShiftFixtures.demoStore()
        let planned = try #require(store.visits.first { $0.status == .planned })

        #expect(store.cancelVisit(id: planned.id, reason: .familyCancelled))

        #expect(store.progress.summary == "3 of 7 visits resolved · 2 completed · 1 cancelled · 4 remaining")
        #expect(store.progress.phrases == [
            "3 of 7 visits resolved",
            "2 completed",
            "1 cancelled",
            "4 remaining"
        ])
    }

    @Test("Adds up across several cancellations and a completion")
    func addsUpAcrossOutcomes() throws {
        let store = ShiftFixtures.demoStore()
        let arrived = try #require(store.visits.first { $0.status == .arrived })
        let planned = store.visits.filter { $0.status == .planned }

        #expect(store.advanceStatus(of: arrived.id, confirmed: true))
        #expect(store.cancelVisit(id: planned[0].id, reason: .familyCancelled))
        #expect(store.cancelVisit(id: planned[1].id, reason: .clientUnavailable))

        let progress = store.progress
        #expect(progress.completed == 3)
        #expect(progress.cancelled == 2)
        #expect(progress.resolved == 5)
        #expect(progress.remaining == 2)
        #expect(progress.percentage == 71)
        #expect(progress.summary == "5 of 7 visits resolved · 3 completed · 2 cancelled · 2 remaining")
    }

    @Test("An empty shift reports zero rather than dividing by zero")
    func handlesEmptyShift() {
        let progress = ShiftProgress(completed: 0, cancelled: 0, total: 0)

        #expect(progress.fraction == 0)
        #expect(progress.percentage == 0)
        #expect(progress.remaining == 0)
    }
}

@Suite("Resetting the demonstration round")
@MainActor
struct ResetTests {
    @Test("Restores statuses, checklists and cancellation records")
    func restoresTheRound() throws {
        let store = ShiftFixtures.demoStore()
        let arrived = try #require(store.visits.first { $0.status == .arrived })
        let planned = try #require(store.visits.first { $0.status == .planned })

        store.setTask(arrived.tasks[1].id, isComplete: true, on: arrived.id)
        #expect(store.cancelVisit(id: planned.id, reason: .officeInstruction))
        #expect(store.advanceStatus(of: arrived.id, confirmed: true))

        store.reset()

        #expect(store.visits.count == 7)
        #expect(store.progress.completed == 2)
        #expect(store.progress.cancelled == 0)
        #expect(store.visits.allSatisfy { $0.cancellation == nil })
        #expect(store.visit(id: arrived.id)?.status == .arrived)
        #expect(store.visit(id: arrived.id)?.completedTaskCount == 1)
        #expect(store.visit(id: planned.id)?.status == .planned)
        #expect(store.activeVisit?.id == arrived.id)
    }

    @Test("Restores both preferences")
    func restoresPreferences() {
        let store = ShiftFixtures.demoStore()
        store.showsCompletedVisitsOnToday = false
        store.confirmsVisitCompletion = true

        store.reset()

        #expect(store.showsCompletedVisitsOnToday)
        #expect(!store.confirmsVisitCompletion)
    }

    @Test("Clears every pending question")
    func clearsPendingQuestions() throws {
        let store = ShiftFixtures.demoStore()
        let arrived = try #require(store.visits.first { $0.status == .arrived })
        let planned = try #require(store.visits.first { $0.status == .planned })

        store.advanceStatus(of: arrived.id)
        store.requestCancellation(id: planned.id)
        #expect(store.pendingCompletion != nil)
        #expect(store.pendingCancelID != nil)

        store.reset()

        #expect(store.pendingCompletion == nil)
        #expect(store.pendingCancelID == nil)
        #expect(store.pendingReturnID == nil)
        #expect(store.blockedTransition == nil)
    }

    @Test("Counts itself, so the interface can react to each one")
    func countsItself() {
        let store = ShiftFixtures.demoStore()
        #expect(store.resetCount == 0)

        store.reset()
        store.reset()

        #expect(store.resetCount == 2)
    }

    @Test("A reset round does not carry a previous mutation back in")
    func doesNotLeakBetweenRounds() throws {
        let store = ShiftFixtures.demoStore()
        let arrived = try #require(store.visits.first { $0.status == .arrived })

        store.setTask(arrived.tasks[1].id, isComplete: true, on: arrived.id)
        #expect(store.visit(id: arrived.id)?.completedTaskCount == 2)

        store.reset()

        #expect(store.visit(id: arrived.id)?.completedTaskCount == 1)
    }
}

@Suite("Pending questions")
@MainActor
struct PendingQuestionTests {
    @Test("A cancellation is only ever composed for a cancellable visit")
    func opensOnlyForCancellableVisits() throws {
        let store = ShiftFixtures.store(visits: [
            ShiftFixtures.visit(reference: "A", start: (8, 0), status: .arrived)
        ])
        let id = try #require(store.visits.first).id

        store.requestCancellation(id: id)

        #expect(store.pendingCancelID == nil)
    }

    @Test("A cancellation request is dismissed without touching the visit")
    func dismissesWithoutTouchingTheVisit() throws {
        let store = ShiftFixtures.store(visits: [
            ShiftFixtures.visit(reference: "A", start: (8, 0), status: .planned)
        ])
        let id = try #require(store.visits.first).id

        store.requestCancellation(id: id)
        #expect(store.pendingCancelID == id)

        store.dismissCancellation()

        #expect(store.pendingCancelID == nil)
        #expect(store.visit(id: id)?.status == .planned)
    }

    @Test("A return request is only opened for an en route visit")
    func returnRequestOnlyForEnRoute() throws {
        let store = ShiftFixtures.store(visits: [
            ShiftFixtures.visit(reference: "A", start: (8, 0), status: .planned)
        ])
        let id = try #require(store.visits.first).id

        store.requestReturnToPlanned(id: id)
        #expect(store.pendingReturnID == nil)

        store.advanceStatus(of: id)
        store.requestReturnToPlanned(id: id)
        #expect(store.pendingReturnID == id)

        store.dismissReturnToPlanned()
        #expect(store.pendingReturnID == nil)
    }

    @Test("Recording a cancellation clears the pending request")
    func recordingClearsThePendingRequest() throws {
        let store = ShiftFixtures.store(visits: [
            ShiftFixtures.visit(reference: "A", start: (8, 0), status: .planned)
        ])
        let id = try #require(store.visits.first).id

        store.requestCancellation(id: id)
        #expect(store.cancelVisit(id: id, reason: .noLongerRequired))

        #expect(store.pendingCancelID == nil)
    }
}
