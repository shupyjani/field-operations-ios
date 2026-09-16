import Foundation

/// Explicit record selections and their refinements.
///
/// A selection is kept as the conditions that produced it, never as the list it
/// produced. That is what lets "only the planned ones" narrow the question the
/// reader actually asked, re-evaluated against the round as it now stands,
/// without anybody re-reading the previous reply as though it were data.
nonisolated extension LocalAssistant {
    private func m(_ pattern: String, _ text: String) -> Bool {
        AssistantInterpreter.matches(pattern, text)
    }

    func selectionAnswer(_ asked: String) -> LocalAnswer? {
        let text = AssistantInterpreter.normalise(asked)
        let reading = AssistantInterpreter.interpret(text)

        // A question about how a control works is not a lookup of records.
        if reading.operation == .explain || reading.subject == .control { return nil }

        // A name-shaped word that resolves to nobody, or to more than one
        // person, belongs to the established router and its clarifications.
        var person: Visit?
        switch AssistantPeople.recognise(text, in: round.visits) {
        case .one(let named): person = named
        case .ambiguous, .unknown: return nil
        case nil: person = nil
        }

        if let answer = countOfPreviousAnswer(text) { return answer }
        if let answer = workRemainingCheck(text) { return answer }
        if let answer = refinement(text) { return answer }
        if let answer = scopeCorrection(text) { return answer }
        if let answer = otherPerson(text) { return answer }
        if let answer = clarifiedByName(text, person: person) { return answer }

        // Everything else reaches the selection engine only when the question
        // states a condition the ordinary families do not carry.
        let query = AssistantSelectionEngine.readSelection(text, person: person)
        guard isExplicitSelection(text, query: query, reading: reading) else { return nil }
        return AssistantSelectionEngine.format(query, in: round)
    }

    /// Whether the question sets a condition that only the selection engine
    /// expresses. Anything narrower is left to the families that already
    /// answer it, so this never takes work away from them.
    private func isExplicitSelection(
        _ text: String,
        query: SelectionQuery,
        reading: AssistantReading
    ) -> Bool {
        if AssistantInterpreter.isWorkRemaining(text) { return true }
        if query.time != nil { return true }
        if !query.excludedStatuses.isEmpty { return true }
        if query.photograph != nil { return true }
        if query.operation == .sumDuration { return true }
        if reading.subject == .task && !query.statuses.isEmpty && reading.done == false { return true }
        if query.conceptIDs.count > 1 && m(#"\bor\b|\band\b"#, text) { return true }
        return false
    }

    // MARK: - Counting what the previous answer returned

    /// "How many is that?" counts what the previous answer returned.
    ///
    /// Recounting the round would silently widen a narrowed question, and would
    /// disagree with the list the reader is looking at.
    private func countOfPreviousAnswer(_ text: String) -> LocalAnswer? {
        guard m(#"^(?:and\s+)?how many (?:are there|is that|are those|was that|were there|were those)\b"#, text),
              let context else { return nil }

        // What was counted follows what the question selected: a question about
        // visits is not answered with a number of tasks.
        let countsTasks = context.query.map { $0.subject == .tasks } ?? !context.taskIDs.isEmpty
        let counted = countsTasks ? context.taskIDs.count : context.visitIDs.count
        let unit = countsTasks ? "task" : "visit"

        return LocalAnswer(
            text: counted == 0
                ? "None. The previous answer matched no \(unit)s."
                : "\(counted) \(counted == 1 ? unit : "\(unit)s") \u{2014} the same \(counted == 1 ? "one" : "ones") as the previous answer.",
            kind: .selection,
            selection: context
        )
    }

    /// "Do those count as work remaining?" — the distinction the round draws
    /// between a record that still stands and work that is still to be done.
    private func workRemainingCheck(_ text: String) -> LocalAnswer? {
        guard m(#"\b(?:those|these)\b.*\b(?:count|work remaining)\b|do (?:those|these) count"#, text),
              m(#"work|remaining"#, text) else { return nil }

        guard let query = context?.query else {
            return LocalAnswer(text: "Which tasks do you mean?", kind: .clarify, selection: context)
        }

        let due = AssistantSelectionEngine.execute(query, in: round).tasks
            .filter { !$0.task.isComplete && !AssistantSelectionEngine.isClosed($0.visit) }

        return LocalAnswer(
            text: "\(due.isEmpty ? "None of these tasks count" : "\(due.count) of these tasks count") as work remaining. Work remaining means unchecked tasks on unresolved visits; closed visits retain their recorded checklists.",
            kind: .selection,
            selection: context
        )
    }

    // MARK: - Refinement

    /// Narrowing the selection already under discussion.
    private func refinement(_ text: String) -> LocalAnswer? {
        guard m(#"\bwho has both\b|^only on visits|\bthose visits\b|\bthese visits\b"#, text) else {
            return nil
        }

        guard var query = context?.query else {
            return LocalAnswer(
                text: "Which visits do you mean? Please repeat the selection.",
                kind: .clarify,
                selection: context
            )
        }

        if m(#"both"#, text) {
            guard query.conceptIDs.count >= 2 else {
                return LocalAnswer(
                    text: "Which two task types do you mean?",
                    kind: .clarify,
                    selection: context
                )
            }
            query.conjunction = .and
            query.subject = .visits
            query.operation = .list
        }
        if m(#"only on visits"#, text) { query.actionable = true }
        if m(#"how many tasks"#, text) {
            query.subject = .tasks
            query.operation = .count
        }

        return AssistantSelectionEngine.format(query, in: round)
    }

    /// "Tasks, not visits" and "only the planned ones" — corrections that
    /// change one condition of the question already asked.
    private func scopeCorrection(_ text: String) -> LocalAnswer? {
        let asksTasks = m(#"^\s*tasks,?\s+not\s+visits[.!?]*$"#, text)
        let asksVisits = m(#"^\s*visits,?\s+not\s+tasks[.!?]*$"#, text)
        let onlyStatus = m(#"^\s*only (?:the )?(planned|completed|cancelled|arrived|en ?route) ones[.!?]*$"#, text)

        guard asksTasks || asksVisits || onlyStatus else { return nil }

        guard var query = context?.query else {
            return LocalAnswer(
                text: "Which visits do you mean? Please repeat the selection.",
                kind: .clarify,
                selection: context
            )
        }

        if asksTasks { query.subject = .tasks }
        if asksVisits { query.subject = .visits }
        if onlyStatus {
            let statuses = AssistantInterpreter.readStatuses(text)
            guard !statuses.isEmpty else { return nil }
            query.statuses = statuses
            query.excludedStatuses = []
        }

        return AssistantSelectionEngine.format(query, in: round)
    }

    /// "Not Priya — the other person", after an answer that named two.
    private func otherPerson(_ text: String) -> LocalAnswer? {
        guard m(#"^\s*not\s+.+[\u{2014}\u{2013},-]\s*the other (?:person|one|client)[?.!]*$"#, text),
              let context else { return nil }

        let named = context.visitIDs.compactMap { round.visit(id: $0) }
        var excluded: Visit?
        if case .one(let visit) = AssistantPeople.recognise(text, in: round.visits) {
            excluded = visit
        }

        let rest = named.filter { $0.id != excluded?.id }
        guard rest.count == 1, let other = rest.first else {
            return LocalAnswer(text: "Which other person did you mean?", kind: .clarify, selection: context)
        }

        // The correction keeps the question that was being asked; only its
        // subject changes.
        return context.wasAboutTasks
            ? answerRewritten("What tasks does \(other.clientName) have?")
            : answerRewritten("Tell me about \(other.clientName)")
    }

    /// A bare name, given in answer to a clarification the assistant asked.
    private func clarifiedByName(_ text: String, person: Visit?) -> LocalAnswer? {
        guard let person, let context else { return nil }

        // "How long is the visit?" → "Which visit did you mean?" → "Halina".
        if context.pending == .duration {
            return LocalAnswer(
                text: "\(person.clientName)\u{2019}s whole visit is scheduled for \(AssistantPhrasing.minutes(AssistantQueries.durationMinutes(person))), from \(AssistantPhrasing.window(person)) (\(person.status.title)).",
                kind: .duration,
                selection: AssistantSelection(
                    visitIDs: [person.id],
                    personID: person.id,
                    lastKind: .duration,
                    property: .duration
                )
            )
        }

        // "How long is the walking task?" → candidates → "Ivor" settles which.
        guard let property = context.property,
              property.isDetail,
              context.taskIDs.count > 1,
              AssistantTaskProperties.read(text) == nil,
              m(#"^\s*[a-z'\- ]{2,40}[.!?]*$"#, text) else { return nil }

        let mine = context.taskIDs.compactMap { id -> TaskMatch? in
            guard let task = person.tasks.first(where: { $0.id == id }) else { return nil }
            return TaskMatch(visit: person, task: task)
        }
        guard !mine.isEmpty else { return nil }

        return taskPropertyReadout(property, among: mine)
    }

    /// Answers a question the assistant rewrote for itself, with the same round
    /// and the same carried context.
    private func answerRewritten(_ question: String) -> LocalAnswer {
        LocalAssistant(round: round, context: context).answer(question)
    }
}
