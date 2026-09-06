import Testing
@testable import AjaniFieldOperations

@Suite("Visit status transitions")
struct VisitStatusTests {
    @Test(
        "Each status advances to exactly one successor",
        arguments: [
            (VisitStatus.planned, VisitStatus.enRoute),
            (VisitStatus.enRoute, VisitStatus.arrived),
            (VisitStatus.arrived, VisitStatus.completed)
        ]
    )
    func advancesThroughTheJourney(from: VisitStatus, to: VisitStatus) {
        #expect(from.successor == to)
        #expect(from.canTransition(to: to))
    }

    @Test("A completed visit has nowhere further to go")
    func completedIsTerminal() {
        #expect(VisitStatus.completed.successor == nil)
        for status in VisitStatus.allCases {
            #expect(!VisitStatus.completed.canTransition(to: status))
        }
    }

    @Test("Stages cannot be skipped")
    func rejectsSkippedStages() {
        #expect(!VisitStatus.planned.canTransition(to: .arrived))
        #expect(!VisitStatus.planned.canTransition(to: .completed))
        #expect(!VisitStatus.enRoute.canTransition(to: .completed))
    }

    @Test("A visit cannot move backwards")
    func rejectsBackwardsTransitions() {
        #expect(!VisitStatus.enRoute.canTransition(to: .planned))
        #expect(!VisitStatus.arrived.canTransition(to: .enRoute))
        #expect(!VisitStatus.completed.canTransition(to: .arrived))
    }

    @Test("A visit cannot transition to the status it already holds")
    func rejectsSelfTransition() {
        for status in VisitStatus.allCases {
            #expect(!status.canTransition(to: status))
        }
    }

    @Test("Only visits under way count as in progress")
    func identifiesInProgressStatuses() {
        #expect(VisitStatus.enRoute.isInProgress)
        #expect(VisitStatus.arrived.isInProgress)
        #expect(!VisitStatus.planned.isInProgress)
        #expect(!VisitStatus.completed.isInProgress)
    }

    @Test("Every status except completed offers an action title")
    func offersActionTitleWhileOpen() {
        #expect(VisitStatus.planned.advanceActionTitle != nil)
        #expect(VisitStatus.enRoute.advanceActionTitle != nil)
        #expect(VisitStatus.arrived.advanceActionTitle != nil)
        #expect(VisitStatus.completed.advanceActionTitle == nil)
    }
}
