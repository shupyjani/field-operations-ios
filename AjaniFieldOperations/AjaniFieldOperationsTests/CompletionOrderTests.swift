import Foundation
import Testing
@testable import AjaniFieldOperations

@Suite("Completion order")
@MainActor
struct CompletionOrderTests {
    private func arrivedStore() -> FieldOperationsStore {
        ShiftFixtures.store(visits: [
            ShiftFixtures.visit(reference: "A", clientName: "Alice Adeyemi", start: (8, 0), status: .arrived),
            ShiftFixtures.visit(reference: "B", clientName: "Bola Bankole", start: (9, 0), status: .planned),
            ShiftFixtures.visit(reference: "C", clientName: "Chi Chukwu", start: (10, 0), status: .planned)
        ])
    }

    @Test("Starts empty: the round's seed completions carry no observed order")
    func startsEmpty() {
        #expect(ShiftFixtures.demoStore().completionOrder.isEmpty)
    }

    @Test("Records a visit when it becomes completed")
    func recordsCompletion() throws {
        let store = arrivedStore()
        let first = try #require(store.visits.first).id

        #expect(store.advanceStatus(of: first, confirmed: true))

        #expect(store.completionOrder == [first])
        #expect(store.sessionCompletions.map(\.reference) == ["A"])
    }

    @Test("Records the order they were worked, not the order they were scheduled")
    func recordsWorkedOrder() throws {
        let store = arrivedStore()
        let a = try #require(store.visits.first).id
        let c = try #require(store.visits.last).id

        // Work the last visit before the middle one.
        #expect(store.advanceStatus(of: a, confirmed: true))
        for _ in 0..<3 { store.advanceStatus(of: c, confirmed: true) }

        #expect(store.completionOrder == [a, c])
        #expect(store.sessionCompletions.map(\.reference) == ["A", "C"])
    }

    @Test("A cancelled visit is not recorded as completed")
    func cancellingRecordsNothing() throws {
        let store = arrivedStore()
        let planned = try #require(store.visits.first { $0.status == .planned }).id

        #expect(store.cancelVisit(id: planned, reason: .familyCancelled))

        #expect(store.completionOrder.isEmpty)
        #expect(store.sessionCompletions.isEmpty)
    }

    @Test("A rejected transition records nothing")
    func rejectedTransitionRecordsNothing() throws {
        let store = arrivedStore()
        let planned = try #require(store.visits.first { $0.status == .planned }).id

        // Planned cannot jump to completed, and another visit is already active.
        #expect(!store.updateStatus(of: planned, to: .completed))
        #expect(!store.advanceStatus(of: planned))

        #expect(store.completionOrder.isEmpty)
    }

    @Test("A visit is never recorded twice")
    func neverRecordsTwice() throws {
        let store = arrivedStore()
        let first = try #require(store.visits.first).id

        #expect(store.advanceStatus(of: first, confirmed: true))
        // A repeated attempt is refused and adds no second event.
        #expect(!store.advanceStatus(of: first, confirmed: true))
        #expect(!store.updateStatus(of: first, to: .completed))

        #expect(store.completionOrder == [first])
    }

    @Test("Reset clears the recorded order")
    func resetClearsTheOrder() throws {
        let store = ShiftFixtures.demoStore()
        let arrived = try #require(store.visits.first { $0.status == .arrived }).id

        #expect(store.advanceStatus(of: arrived, confirmed: true))
        #expect(store.completionOrder.count == 1)

        store.reset()

        #expect(store.completionOrder.isEmpty)
        #expect(store.sessionCompletions.isEmpty)
    }

    @Test("The assistant reads the recorded order from the store")
    func assistantReadsTheOrder() throws {
        let store = ShiftFixtures.demoStore()
        let arrived = try #require(store.visits.first { $0.status == .arrived })

        #expect(store.advanceStatus(of: arrived.id, confirmed: true))

        let answer = LocalAssistant(round: store.assistantRound).answer("Which visit did I just finish?")

        #expect(answer.text.contains(arrived.clientName))
        #expect(answer.text.contains("most recently this session"))
    }

    @Test("The round the assistant reads follows the store's live state")
    func assistantRoundFollowsTheStore() throws {
        let store = ShiftFixtures.demoStore()

        #expect(store.assistantRound.progress.completed == 2)
        #expect(store.assistantRound.active?.reference == "AV-1043")

        let arrived = try #require(store.visits.first { $0.status == .arrived }).id
        #expect(store.advanceStatus(of: arrived, confirmed: true))

        #expect(store.assistantRound.progress.completed == 3)
        #expect(store.assistantRound.active == nil)
        #expect(store.assistantRound.upNext?.reference == "AV-1044")
    }

    @Test("A cancellation shows in the round the assistant reads")
    func assistantRoundShowsCancellations() throws {
        let store = ShiftFixtures.demoStore()
        let planned = try #require(store.visits.first { $0.status == .planned })

        #expect(store.cancelVisit(id: planned.id, reason: .officeInstruction, note: "Office called"))

        let answer = LocalAssistant(round: store.assistantRound)
            .answer("Why was \(planned.clientName)'s visit cancelled?")

        #expect(answer.text.contains("Office instruction"))
        #expect(answer.text.contains("Office called"))
    }
}
