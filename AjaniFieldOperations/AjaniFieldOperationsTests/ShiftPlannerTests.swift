import Foundation
import Testing
@testable import AjaniFieldOperations

@Suite("Visit ordering")
struct VisitOrderingTests {
    @Test("Visits are ordered by scheduled start time")
    func ordersByScheduledStart() {
        let visits = [
            ShiftFixtures.visit(reference: "C", start: (13, 30)),
            ShiftFixtures.visit(reference: "A", start: (7, 45)),
            ShiftFixtures.visit(reference: "B", start: (11, 0))
        ]

        let ordered = ShiftPlanner.chronological(visits)

        #expect(ordered.map(\.reference) == ["A", "B", "C"])
    }

    @Test("Visits sharing a start time fall back to reference order")
    func breaksTiesByReference() {
        let visits = [
            ShiftFixtures.visit(reference: "AV-1002", start: (9, 0)),
            ShiftFixtures.visit(reference: "AV-1001", start: (9, 0))
        ]

        let ordered = ShiftPlanner.chronological(visits)

        #expect(ordered.map(\.reference) == ["AV-1001", "AV-1002"])
    }

    @Test("Ordering leaves an empty schedule empty")
    func handlesEmptySchedule() {
        #expect(ShiftPlanner.chronological([]).isEmpty)
    }
}

@Suite("Shift progress")
struct ShiftProgressTests {
    @Test("Progress counts completed visits against the total")
    func countsCompletedVisits() {
        let visits = [
            ShiftFixtures.visit(reference: "A", start: (8, 0), status: .completed),
            ShiftFixtures.visit(reference: "B", start: (9, 0), status: .completed),
            ShiftFixtures.visit(reference: "C", start: (10, 0), status: .arrived),
            ShiftFixtures.visit(reference: "D", start: (11, 0), status: .planned)
        ]

        let progress = ShiftPlanner.progress(for: visits)

        #expect(progress.completed == 2)
        #expect(progress.total == 4)
        #expect(progress.remaining == 2)
        #expect(progress.fraction == 0.5)
        #expect(progress.percentage == 50)
    }

    @Test("An empty shift reports zero progress rather than dividing by zero")
    func handlesEmptyShift() {
        let progress = ShiftPlanner.progress(for: [])

        #expect(progress.total == 0)
        #expect(progress.remaining == 0)
        #expect(progress.fraction == 0)
        #expect(progress.percentage == 0)
    }

    @Test("A finished shift reports full progress")
    func handlesFinishedShift() {
        let visits = [
            ShiftFixtures.visit(reference: "A", start: (8, 0), status: .completed),
            ShiftFixtures.visit(reference: "B", start: (9, 0), status: .completed)
        ]

        let progress = ShiftPlanner.progress(for: visits)

        #expect(progress.remaining == 0)
        #expect(progress.percentage == 100)
    }
}

@Suite("Next visit")
struct NextVisitTests {
    @Test("A visit already under way takes priority over later planned visits")
    func prefersVisitInProgress() {
        let visits = [
            ShiftFixtures.visit(reference: "A", start: (8, 0), status: .completed),
            ShiftFixtures.visit(reference: "B", start: (9, 0), status: .planned),
            ShiftFixtures.visit(reference: "C", start: (10, 0), status: .enRoute)
        ]

        #expect(ShiftPlanner.upNext(in: visits)?.reference == "C")
    }

    @Test("Without a visit in progress the earliest planned visit is next")
    func fallsBackToEarliestPlanned() {
        let visits = [
            ShiftFixtures.visit(reference: "C", start: (13, 0), status: .planned),
            ShiftFixtures.visit(reference: "A", start: (8, 0), status: .completed),
            ShiftFixtures.visit(reference: "B", start: (11, 0), status: .planned)
        ]

        #expect(ShiftPlanner.upNext(in: visits)?.reference == "B")
    }

    @Test("A fully completed shift has no next visit")
    func returnsNilWhenEverythingIsComplete() {
        let visits = [
            ShiftFixtures.visit(reference: "A", start: (8, 0), status: .completed),
            ShiftFixtures.visit(reference: "B", start: (9, 0), status: .completed)
        ]

        #expect(ShiftPlanner.upNext(in: visits) == nil)
    }

    @Test("An empty schedule has no next visit")
    func returnsNilForEmptySchedule() {
        #expect(ShiftPlanner.upNext(in: []) == nil)
    }
}
