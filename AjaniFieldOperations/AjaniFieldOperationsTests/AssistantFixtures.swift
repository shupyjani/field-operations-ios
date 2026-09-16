import Foundation
@testable import AjaniFieldOperations

/// The demonstration round, as the assistant reads it.
enum AssistantFixtures {
    static var visits: [Visit] {
        DemoFieldData.visits(on: ShiftFixtures.referenceDate, calendar: ShiftFixtures.calendar)
    }

    static func round(
        visits: [Visit]? = nil,
        completionOrder: [Visit.ID] = [],
        showsCompleted: Bool = true,
        confirms: Bool = false
    ) -> AssistantRound {
        AssistantRound(
            visits: visits ?? Self.visits,
            workerFirstName: DemoFieldData.worker.firstName,
            shiftWindow: "7:30–15:45",
            round: "Southside · Round 4",
            completionOrder: completionOrder,
            showsCompletedVisitsOnToday: showsCompleted,
            confirmsVisitCompletion: confirms
        )
    }

    static func visit(_ reference: String, in visits: [Visit]? = nil) -> Visit {
        let all = visits ?? Self.visits
        return all.first { $0.reference == reference } ?? all[0]
    }

    /// Answers a question against the opening round.
    static func ask(_ question: String, round: AssistantRound? = nil, context: AssistantSelection? = nil) -> LocalAnswer {
        LocalAssistant(round: round ?? Self.round(), context: context).answer(question)
    }

    /// A round with every visit resolved except the named references.
    static func round(remainingOnly references: [String]) -> AssistantRound {
        let updated = visits.map { visit -> Visit in
            guard !references.contains(visit.reference) else { return visit }
            var copy = visit
            copy.status = .completed
            return copy
        }
        return round(visits: updated)
    }
}

/// A provider that answers with whatever the test hands it.
final class StubAssistantProvider: AssistantProviding, @unchecked Sendable {
    enum Behaviour: Sendable {
        case reply(String)
        case unavailable
        case slow(String, seconds: Double)
    }

    private let behaviour: Behaviour
    private(set) var receivedQuestions: [String] = []
    private(set) var receivedHistory: [[AssistantHistoryEntry]] = []
    private(set) var receivedSnapshots: [AssistantSnapshot] = []

    init(_ behaviour: Behaviour) {
        self.behaviour = behaviour
    }

    func reply(
        to question: String,
        history: [AssistantHistoryEntry],
        snapshot: AssistantSnapshot
    ) async -> String? {
        receivedQuestions.append(question)
        receivedHistory.append(history)
        receivedSnapshots.append(snapshot)

        switch behaviour {
        case .reply(let text):
            return text
        case .unavailable:
            return nil
        case .slow(let text, let seconds):
            try? await Task.sleep(for: .seconds(seconds))
            return text
        }
    }
}
