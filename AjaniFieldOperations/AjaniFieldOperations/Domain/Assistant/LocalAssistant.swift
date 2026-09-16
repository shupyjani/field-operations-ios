import Foundation

/// The deterministic assistant.
///
/// Answers are computed from the round it is handed and nothing else: no clock,
/// no network, no stored copy of the visits. It is a bounded recogniser over the
/// app's own vocabulary rather than general language understanding, so a question
/// it does not recognise is said to be unrecognised instead of guessed at.
///
/// Two boundaries hold whatever the sentence contains. It never gives clinical
/// advice, and it never changes anything — a request to act is answered by naming
/// the control that does it.
nonisolated struct LocalAssistant {
    let round: AssistantRound
    /// What the previous answer named, so a follow-up has a referent.
    let context: AssistantSelection?

    init(round: AssistantRound, context: AssistantSelection? = nil) {
        self.round = round
        self.context = context
    }

    func answer(_ question: String) -> LocalAnswer {
        // Meaning-preserving only: phones produce curly quotes by default and
        // every pattern below is written with the plain ones.
        let trimmed = AssistantInterpreter.normalise(question)
        guard !trimmed.isEmpty else {
            return LocalAnswer(text: AssistantCopy.welcome, kind: .unsupported)
        }

        // The whole sentence is classified before it is broken up, so splitting
        // can never let half a request slip past a boundary the whole one meets.
        if let boundary = boundaryAnswer(trimmed) { return boundary }

        // An ordinal or a correction rewrites the question before anything reads
        // it, so the rest of the pipeline sees a question that names its subject.
        switch resolveReference(trimmed) {
        case .rewritten(let rewritten):
            return answerClauses(rewritten)
        case .unresolved(let clarification):
            return clarification
        case .unchanged:
            return answerClauses(trimmed)
        }
    }

    /// Answers a sentence that may carry more than one request.
    private func answerClauses(_ asked: String) -> LocalAnswer {
        let clauses = splitClauses(asked)
        guard clauses.count > 1 else { return answerOne(asked, context: context) }

        var parts: [LocalAnswer] = []
        var carried = context

        for clause in clauses {
            let answer = answerOne(clause, context: carried)
            // A clause nobody can answer collapses the whole attempt, rather
            // than producing half a reply.
            guard answer.kind != .unsupported, answer.kind != .clarify else {
                return answerOne(asked, context: context)
            }

            parts.append(answer)
            // Whoever the clause just answered about becomes the referent for
            // the next one, so "and how many tasks do they have?" has a subject.
            if let selection = answer.selection, !selection.isEmpty {
                carried = selection
            }
        }

        var seen = Set<String>()
        let text = parts.map(\.text).filter { seen.insert($0).inserted }.joined(separator: " ")

        return LocalAnswer(
            text: text,
            kind: parts.count > 1 ? .compound : (parts.first?.kind ?? .unsupported),
            selection: parts.last?.selection ?? context
        )
    }

    private func answerOne(_ asked: String, context: AssistantSelection?) -> LocalAnswer {
        LocalAssistant(round: round, context: context).answerSingle(asked)
    }

    /// A boundary answer, or `nil` when the question is an ordinary one.
    private func boundaryAnswer(_ asked: String) -> LocalAnswer? {
        switch AssistantClassifier.classify(asked) {
        case .disclosure:
            return LocalAnswer(text: AssistantCopy.disclosureRefusal, kind: .disclosure, selection: context)
        case .advice, .clinical:
            return LocalAnswer(text: AssistantCopy.clinicalRefusal, kind: .clinical, selection: context)
        case .mutation:
            if isInstructional(asked) {
                if let absent = AssistantGuidance.findAbsentControl(asked) {
                    return LocalAnswer(text: absent.text, kind: .absentControl, selection: context)
                }
                if let guidance = AssistantGuidance.find(asked) {
                    return LocalAnswer(text: guidance.text, kind: .guidance, selection: context)
                }
            }
            return LocalAnswer(text: mutationRefusal(asked), kind: .mutation, selection: context)
        case .demographic:
            return LocalAnswer(text: AssistantCopy.demographic, kind: .demographic, selection: context)
        case .lookup, .open:
            return nil
        }
    }

    private func answerSingle(_ asked: String) -> LocalAnswer {
        // Boundaries first. None of these may be talked past, and none of them
        // may be sent to a provider to be refused remotely.
        switch AssistantClassifier.classify(asked) {
        case .disclosure:
            return LocalAnswer(text: AssistantCopy.disclosureRefusal, kind: .disclosure)
        case .advice, .clinical:
            return LocalAnswer(text: AssistantCopy.clinicalRefusal, kind: .clinical)
        case .mutation:
            // "How do I cancel a visit?" names the action a control performs and
            // is a question about that control. "Cancel it for me" asks the
            // assistant to act. Only the second is a mutation.
            if isInstructional(asked) {
                if let absent = AssistantGuidance.findAbsentControl(asked) {
                    return LocalAnswer(text: absent.text, kind: .absentControl)
                }
                if let guidance = AssistantGuidance.find(asked) {
                    return LocalAnswer(text: guidance.text, kind: .guidance)
                }
            }
            return LocalAnswer(text: mutationRefusal(asked), kind: .mutation)
        case .demographic:
            return LocalAnswer(text: AssistantCopy.demographic, kind: .demographic)
        case .lookup, .open:
            break
        }

        // A control the app does not have is said plainly rather than searched for.
        if let absent = AssistantGuidance.findAbsentControl(asked) {
            return LocalAnswer(text: absent.text, kind: .absentControl)
        }

        for resolve in [
            conversationHistory, clockQuestion, elapsedTimeQuestion,
            selectionAnswer, anyMore, followUp, namedTaskLookup, taskPropertyQuestion,
            cancellationRecord, completionHistory, comparatorQuestion,
            contactQuestion, similarityQuestion, dressingQuestion, conceptQuestion,
            finishByQuestion, scheduleRun, positionalQuestion,
            counting, activeOrNext, statusListing, priorityQuestion, noteQuestion,
            taskQuestion, scheduleQuestion, personQuestion
        ] {
            if let answer = resolve(asked) { return answer }
        }

        // Guidance last among the recognisers: a question that names a person or
        // a status is about the round, not about the control that changes it.
        if let guidance = AssistantGuidance.find(asked) {
            return LocalAnswer(text: guidance.text, kind: .guidance)
        }

        return LocalAnswer(text: AssistantCopy.unsupported, kind: .unsupported)
    }

    // MARK: - Boundaries

    /// Whether the question asks how something works rather than asking for it
    /// to be done. An explicit imperative disqualifies it however it is phrased.
    private func isInstructional(_ asked: String) -> Bool {
        // Asking the assistant to do it is never instructional, however it is
        // phrased: "can you cancel it" is a request, "can I cancel it" is a
        // question about what the app allows.
        guard !matches(#"\bfor me\b|\bplease\b|\bgo ahead\b|\b(can|could|would|will) you\b"#, asked) else {
            return false
        }

        return matches(#"^\s*(how|what happens|why|where|when)\b"#, asked)
            || matches(#"\b(how do i|how can i|how does|how is|what happens (when|if|to))\b"#, asked)
            || matches(#"\b(can i|could i|am i able|is it possible|is there a way)\b"#, asked)
    }

    /// A request to act, answered by naming the control that does it.
    private func mutationRefusal(_ asked: String) -> String {
        let opening = "I can\u{2019}t change anything — I only read the round. "

        if matches(#"\bcancel"#, asked) {
            return opening + "To cancel a visit, open a Planned or En route visit and choose \u{201C}Cancel visit\u{201D}, then pick a reason."
        }
        if matches(#"\b(complete|finish|close)\b"#, asked) {
            return opening + "To complete a visit, open it once it is Arrived and use \u{201C}\(VisitStatus.arrived.advanceActionTitle ?? "")\u{201D}."
        }
        if matches(#"\b(tick|untick|check|uncheck)\b"#, asked) {
            return opening + "To tick a task, open the visit once it is Arrived and tap the task. Planned and En route checklists are locked."
        }
        if matches(#"\b(start|travel|begin)\b"#, asked) {
            return opening + "To start a visit, open it and use \u{201C}\(VisitStatus.planned.advanceActionTitle ?? "")\u{201D}. Only one visit can be active at a time."
        }
        if matches(#"\b(restore|reopen|undo|return|revert)\b"#, asked) {
            return opening + "\u{201C}Return to Planned\u{201D} applies to an En route visit. A Completed or Cancelled visit cannot be reopened; resetting the round restores it entirely."
        }
        if matches(#"\breset\b"#, asked) {
            return opening + "More has a \u{201C}Reset demonstration round\u{201D} button that restores the original round."
        }

        return opening + "Every change is made with the app\u{2019}s own controls, on Today or in a visit\u{2019}s detail."
    }

    // MARK: - Clauses, ordinals and corrections

    /// Splits a sentence that carries more than one request.
    ///
    /// Only a part that opens like a question of its own becomes a clause:
    /// conjunctions inside one clause — "washing and dressing", "planned and
    /// cancelled" — are left intact.
    private func splitClauses(_ text: String) -> [String] {
        let parts = text
            .replacingOccurrences(of: #"\s*(?:\band\b|\bbut\b|;|,\s*(?=and\b))\s*"#, with: "\u{0000}", options: [.regularExpression, .caseInsensitive])
            .components(separatedBy: "\u{0000}")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        guard parts.count > 1 else { return [text] }

        let opener = #"\b(who|what|which|when|where|how many|how much|how long|how do|is there|are there|does|do|can)\b"#
        var clauses: [String] = []

        for part in parts {
            if clauses.isEmpty {
                clauses.append(part)
            } else if matches(opener, part) {
                clauses.append(part)
            } else {
                // Not a question of its own — it belongs to the clause before it.
                clauses[clauses.count - 1] += " and \(part)"
            }
        }

        return clauses.isEmpty ? [text] : clauses
    }

    private enum Reference {
        case unchanged
        case rewritten(String)
        case unresolved(LocalAnswer)
    }

    /// Resolves an ordinal or a correction into a question that names its own
    /// subject, or says it cannot be resolved safely.
    private func resolveReference(_ asked: String) -> Reference {
        let named = context.map { $0.visitIDs.compactMap { round.visit(id: $0) } } ?? []

        // "the first one", "the second visit"
        if let range = asked.range(of: #"\b(?:the )?(first|second|third|fourth|fifth)\s+(one|visit|person|client)\b"#, options: [.regularExpression, .caseInsensitive]) {
            let ordinals = ["first": 0, "second": 1, "third": 2, "fourth": 3, "fifth": 4]
            let word = String(asked[range]).lowercased()
            guard let position = ordinals.first(where: { word.contains($0.key) })?.value else {
                return .unchanged
            }

            guard !named.isEmpty else {
                return .unresolved(LocalAnswer(
                    text: "There is no earlier result to count through. Which person did you mean?",
                    kind: .clarify,
                    selection: context
                ))
            }
            guard position < named.count else {
                return .unresolved(LocalAnswer(
                    text: "There is no result at that position. Which listed person did you mean?",
                    kind: .clarify,
                    selection: context
                ))
            }

            return .rewritten(asked.replacingCharacters(in: range, with: named[position].clientName))
        }

        // "No, I meant Halina" / "Actually, I meant the second visit"
        if matches(#"^\s*(no|actually|sorry)?[,\s]*i meant\b"#, asked) {
            let remainder = asked.replacingOccurrences(
                of: #"^\s*(no|actually|sorry)?[,\s]*i meant\s*"#,
                with: "",
                options: [.regularExpression, .caseInsensitive]
            )

            guard let match = AssistantPeople.recognise(remainder, in: round.visits) else {
                return .unresolved(LocalAnswer(
                    text: "Which person on the round did you mean?",
                    kind: .clarify,
                    selection: context
                ))
            }

            switch match {
            case .one(let visit):
                // Re-ask the question the correction is correcting.
                let wasTasks = context?.wasAboutTasks ?? false
                return .rewritten(wasTasks
                    ? "What tasks does \(visit.clientName) have?"
                    : "Tell me about \(visit.clientName)")
            case .ambiguous(let candidates):
                return .unresolved(LocalAnswer(
                    text: "More than one person on the round matches that. Did you mean \(AssistantPhrasing.names(candidates))?",
                    kind: .ambiguous,
                    selection: context
                ))
            case .unknown(let name):
                return .unresolved(LocalAnswer(
                    text: AssistantCopy.notFoundPerson(name),
                    kind: .notFound,
                    selection: context
                ))
            }
        }

        return .unchanged
    }

    // MARK: - Comparators

    /// "Does anyone have more than three tasks today?"
    private func comparatorQuestion(_ asked: String) -> LocalAnswer? {
        guard matches(#"\btask"#, asked),
              let comparison = AssistantQueries.readComparison(asked) else {
            return nil
        }

        let phrase = "\(comparison.comparator.phrase) \(comparison.count) recorded \(comparison.count == 1 ? "task" : "tasks")"
        let matching = AssistantQueries.visits(round.visits, taskCount: comparison.comparator, comparison.count)

        guard !matching.isEmpty else {
            return LocalAnswer(
                text: "No. No visit on today\u{2019}s round has \(phrase).",
                kind: .taskCount
            )
        }

        let listed = matching.map { "\($0.clientName) (\(AssistantPhrasing.plural($0.tasks.count, "task")))" }
        return LocalAnswer(
            text: "\(AssistantPhrasing.plural(matching.count, "visit")) \(matching.count == 1 ? "has" : "have") \(phrase): \(AssistantPhrasing.list(listed)).",
            kind: .taskCount,
            selection: AssistantSelection(visitIDs: matching.map(\.id), lastKind: .taskCount)
        )
    }

    // MARK: - Concepts

    /// A question about an operational idea rather than a literal word.
    private func conceptQuestion(_ asked: String) -> LocalAnswer? {
        // A question about one person's checklist is answered by the task
        // family, which can name the person.
        if case .one = AssistantPeople.recognise(asked, in: round.visits) { return nil }

        // A checklist question, work framed as work, or an "any\u{2026}" question.
        // Anything else is read literally before any concept is considered.
        guard matches(#"\b(task|tasks|checklist|any|anyone|anybody|who)\b"#, asked)
            || matches(#"\b(have|has|need|needs) to\b|\bdo i (have|need)\b|\bwho (needs|has) to\b"#, asked)
        else { return nil }

        // Hygiene and mobility are broad on purpose: they gather what is
        // recorded rather than asserting that anything is absent.
        if let broad = AssistantConcepts.resolve(asked), ["hygiene", "mobility"].contains(broad.id) {
            return conceptAnswer(broad)
        }

        // The precise concepts exist to tell look-alike actions apart and must
        // be consulted before any literal word search. The rest wait until a
        // literal search has had its turn, so a concept never talks over a task
        // the reader named outright.
        guard let precise = AssistantConcepts.resolve(asked, preciseOnly: true) else { return nil }
        return conceptAnswer(precise)
    }

    private func conceptAnswer(_ concept: TaskConcept) -> LocalAnswer {
        let matches = AssistantConcepts.tasks(in: round.visits, for: concept)

        if !matches.isEmpty {
            let visits = Array(Set(matches.map(\.visit.id)))
            return LocalAnswer(
                text: "\(AssistantPhrasing.plural(visits.count, "visit")) \(visits.count == 1 ? "has" : "have") a matching task: \(matches.map(AssistantPhrasing.describe).joined(separator: "; ")).",
                kind: .taskSearch,
                selection: AssistantSelection(
                    visitIDs: matches.map(\.visit.id),
                    taskIDs: matches.map(\.task.id),
                    personID: visits.count == 1 ? visits[0] : nil,
                    lastKind: .taskSearch
                )
            )
        }

        // An absence is useful rather than merely correct: nothing administers
        // medication, and two tasks prompt it.
        if let related = AssistantConcepts.related(to: concept) {
            let nearby = AssistantConcepts.tasks(in: round.visits, for: related)
            if !nearby.isEmpty {
                return LocalAnswer(
                    text: "No task on today\u{2019}s round explicitly records \(concept.noun). What is recorded is \(related.noun): \(nearby.map(AssistantPhrasing.describe).joined(separator: "; ")).",
                    kind: .concept,
                    selection: AssistantSelection(
                        visitIDs: nearby.map(\.visit.id),
                        taskIDs: nearby.map(\.task.id),
                        lastKind: .taskSearch
                    )
                )
            }
        }

        return LocalAnswer(
            text: "No task on today\u{2019}s round records \(concept.noun).",
            kind: .concept
        )
    }

    /// "Any dressing tasks?" — two unrelated jobs share the word, so both are
    /// shown, labelled, rather than one being silently chosen.
    private func dressingQuestion(_ asked: String) -> LocalAnswer? {
        guard AssistantConcepts.isVagueDressing(asked) else { return nil }
        if case .one = AssistantPeople.recognise(asked, in: round.visits) { return nil }

        let categories = AssistantConcepts.dressingCategories(in: round.visits)
        var parts: [String] = []

        if !categories.personal.isEmpty {
            parts.append("personal dressing — \(categories.personal.map(AssistantPhrasing.describe).joined(separator: "; "))")
        }
        if !categories.wound.isEmpty {
            parts.append("wound dressing — \(categories.wound.map(AssistantPhrasing.describe).joined(separator: "; "))")
        }

        guard !parts.isEmpty else {
            return LocalAnswer(text: "No task on today\u{2019}s round mentions dressing.", kind: .concept)
        }

        let all = categories.personal + categories.wound
        return LocalAnswer(
            text: "\u{201C}Dressing\u{201D} covers two different jobs here. \(AssistantPhrasing.list(parts)).",
            kind: .concept,
            selection: AssistantSelection(
                visitIDs: all.map(\.visit.id),
                taskIDs: all.map(\.task.id),
                lastKind: .taskSearch
            )
        )
    }

    // MARK: - Contact

    /// "Do I need to ring any client before visiting?"
    private func contactQuestion(_ asked: String) -> LocalAnswer? {
        guard matches(#"\b(ring|ringing|call|calling|phone|phoning|contact|contacts|contacted|contacting)\b"#, asked),
              matches(#"\b(need|have to|must|should i|do i|any|anyone|which|who)\b"#, asked) else {
            return nil
        }

        let mentions = AssistantQueries.contactMentions(in: round.visits)
        let beforehand = matches(#"\b(before|prior to|ahead of|in advance|pre[- ]?visit)\b"#, asked)

        func list(_ entries: [AssistantQueries.ContactMention]) -> String {
            entries.map { "\($0.visit.clientName) — \($0.text)" }.joined(separator: " ")
        }

        if beforehand {
            let preVisit = mentions.filter { $0.kind == .preVisit }
            guard !preVisit.isEmpty else {
                return LocalAnswer(
                    text: "No. No note on today\u{2019}s round asks you to ring a client before visiting.",
                    kind: .contact
                )
            }
            return LocalAnswer(
                text: "\(AssistantPhrasing.plural(preVisit.count, "visit")) asks for a call beforehand: \(list(preVisit))",
                kind: .contact,
                selection: AssistantSelection(visitIDs: preVisit.map(\.visit.id), lastKind: .contact)
            )
        }

        let instructing = mentions.filter { $0.kind == .preVisit || $0.kind == .outgoing }
        if !instructing.isEmpty {
            return LocalAnswer(
                text: "\(AssistantPhrasing.plural(instructing.count, "record")) asks you to make contact: \(list(instructing))",
                kind: .contact,
                selection: AssistantSelection(visitIDs: instructing.map(\.visit.id), lastKind: .contact)
            )
        }

        // An incoming call and a conditional escalation are both real records,
        // and neither is an instruction to telephone anyone.
        let other = mentions.filter { $0.kind == .incoming || $0.kind == .conditional }
        return LocalAnswer(
            text: other.isEmpty
                ? "No visit records an instruction to contact anyone."
                : "No task or note instructs you to make a call. The round mentions contact \(other.count == 1 ? "once" : "\(other.count) times") — \(list(other)) — but as an expected call and a conditional escalation.",
            kind: .contact,
            selection: AssistantSelection(visitIDs: other.map(\.visit.id), lastKind: .contact)
        )
    }

    // MARK: - Similarity

    /// "Are any of her tasks similar to anyone else's?"
    private func similarityQuestion(_ asked: String) -> LocalAnswer? {
        guard matches(#"\b(similar|resemble|resembles|like (?:anyone|any other)|same as|overlap)\b"#, asked) else {
            return nil
        }

        let visit: Visit?
        if case .one(let named) = AssistantPeople.recognise(asked, in: round.visits) {
            visit = named
        } else if let personID = context?.personID {
            visit = round.visit(id: personID)
        } else {
            visit = nil
        }

        guard let visit else {
            return LocalAnswer(
                text: "Whose tasks did you mean? Name a person on the round and I will compare their checklist.",
                kind: .clarify,
                selection: context
            )
        }

        let found = AssistantQueries.similarTasks(in: round.visits, to: visit)
        guard !found.isEmpty else {
            return LocalAnswer(
                text: "No clearly similar recorded task was found elsewhere on the round. \(visit.clientName)\u{2019}s tasks share no more than the odd word with anyone else\u{2019}s, and I won\u{2019}t treat two differently worded jobs as the same one.",
                kind: .similar,
                selection: AssistantSelection(visitIDs: [visit.id], personID: visit.id, lastKind: .similar)
            )
        }

        let listed = found.prefix(3).map {
            "\($0.task.title) resembles \($0.other.clientName)\u{2019}s \($0.candidate.title)"
        }
        return LocalAnswer(
            text: "\(AssistantPhrasing.list(Array(listed))).",
            kind: .similar,
            selection: AssistantSelection(
                visitIDs: [visit.id] + found.prefix(3).map(\.other.id),
                personID: visit.id,
                lastKind: .similar
            )
        )
    }

    // MARK: - Follow-ups

    /// Questions that only mean something after a previous answer.
    private func followUp(_ asked: String) -> LocalAnswer? {
        guard let context, !context.isEmpty else { return nil }

        // The tasks the last answer named are open to a bare property question:
        // "How long?" after a list means those tasks and nothing else.
        let namedTasks = context.taskIDs.compactMap { task(id: $0) }
        let namedVisits = context.visitIDs.compactMap { round.visit(id: $0) }
        let namedPerson = context.personID.flatMap { round.visit(id: $0) }

        // A referent the round no longer holds is no referent at all. The
        // question is then answered as if nothing had been named, rather than
        // against an empty set that would report zero of everything.
        guard !namedTasks.isEmpty || !namedVisits.isEmpty || namedPerson != nil else { return nil }

        let referring = matches(#"^(and |so )?(what about|how about)\b"#, asked)
            || matches(#"\b(that|those|it|they|them|this)\b"#, asked)
            || matches(#"\b(she|he|her|his|their|hers|theirs)\b"#, asked)
            || matches(#"^(is it|are they|has it|have they|was it)\b"#, asked)
            || (!namedTasks.isEmpty && bareProperty(asked))
            || (context.field != nil && matches(#"\b(additional note|cancellation note|operational notes?|travel)\b"#, asked))

        guard referring else { return nil }

        // "What about now?" re-reads the task under discussion from the round
        // as it now stands, rather than repeating what was said about it.
        if matches(#"^(?:what about now|and now)[?.!]*$"#, asked), namedTasks.count == 1 {
            let pair = namedTasks[0]
            return LocalAnswer(
                text: "\(pair.task.isComplete ? "Checked" : "Unchecked"). \(pair.visit.clientName)\u{2019}s \u{2018}\(pair.task.title)\u{2019} task is currently \(pair.task.isComplete ? "checked" : "unchecked").",
                kind: .taskDetail,
                selection: context
            )
        }

        // "What other tasks does she have?" — the rest of one person's
        // checklist, other than the task just discussed.
        if matches(#"\b(other|another)\b"#, asked), matches(#"\btasks?\b"#, asked) {
            let owner = namedPerson ?? (namedTasks.count == 1 ? namedTasks[0].visit : nil)
            if let owner, let answer = otherTasks(of: owner, excluding: namedTasks) {
                return answer
            }
        }

        // A task the last answer named — or several, in which case the question
        // is narrowed before anybody is asked to choose between them.
        if !namedTasks.isEmpty, let answer = taskPropertyAnswer(asked, among: namedTasks) {
            return answer
        }

        // A recorded field the last answer read, returned to without naming
        // the person again.
        if let visit = namedPerson ?? (namedVisits.count == 1 ? namedVisits[0] : nil),
           let answer = carriedField(asked, visit: visit) {
            return answer
        }

        // A person the last answer named.
        if let visit = namedPerson, let answer = personFacts(asked, visit: visit) {
            return answer
        }

        // A set the last answer named. What is being counted is read from the
        // question, so "how many tasks" is never answered with a visit count.
        if matches(#"\bhow many\b"#, asked), !namedVisits.isEmpty {
            let visits = namedVisits

            if matches(#"\btasks?\b"#, asked) {
                let total = visits.reduce(0) { $0 + $1.tasks.count }
                let done = visits.reduce(0) { $0 + $1.completedTaskCount }
                let whose = visits.count == 1 ? visits[0].clientName : "those visits"
                return LocalAnswer(
                    text: "\(AssistantPhrasing.plural(total, "task")) \u{2014} \(whose) \(visits.count == 1 ? "has" : "have") \(done) ticked and \(total - done) unticked.",
                    kind: .taskCount,
                    selection: context
                )
            }

            return LocalAnswer(
                text: "\(AssistantPhrasing.plural(visits.count, "visit")) in that result.",
                kind: .counts,
                selection: context
            )
        }

        return nil
    }

    /// "What dose is recorded for Halina?" \u{2014} a recorded detail, looked up on
    /// the tasks that could plausibly carry it.
    ///
    /// A read-back and nothing more. If the round wrote a value down it is
    /// repeated; if it did not, that is said. Nothing is inferred, and no
    /// answer here tells anybody what to do about what it found.
    private func taskPropertyQuestion(_ asked: String) -> LocalAnswer? {
        guard let property = AssistantTaskProperties.read(asked), property.isDetail else { return nil }

        // "How long is his visit?" asks about the slot, not about any task
        // inside it. Naming a task brings it back to the checklist.
        if matches(#"\bvisits?\b"#, asked), !matches(#"\btasks?\b|\bchecklist\b"#, asked) {
            return nil
        }

        // A bare "how long" with no person and no concept is a question about a
        // visit, and the schedule family answers that.
        var person: Visit?
        if let match = AssistantPeople.recognise(asked, in: round.visits), case .one(let visit) = match {
            person = visit
        } else if matches(#"\b(her|his|their|that|this)\b"#, asked) {
            person = context?.personID.flatMap { round.visit(id: $0) }
        }

        // "Which dressing type?" reads the wound-dressing record specifically.
        let concept = property == .dressingType
            ? AssistantConcepts.concept(id: "wound-dressing")
            : AssistantConcepts.resolve(asked)

        let pool = person.map { [$0] } ?? round.visits
        var candidates = AssistantQueries.allVisits(pool).flatMap { visit in
            visit.tasks.map { TaskMatch(visit: visit, task: $0) }
        }

        // A task named outright outranks any concept reading of the sentence.
        let lowered = asked.lowercased()
        let literal = candidates.filter { lowered.contains($0.task.title.lowercased()) }
        if !literal.isEmpty {
            candidates = literal
        } else if let concept {
            candidates = candidates.filter { matches(concept.label, $0.task.title) }
        } else if person == nil {
            // Nothing names a person and nothing names a kind of task: there is
            // no set to read a property from.
            return nil
        }

        guard !candidates.isEmpty else {
            guard let person else { return nil }
            return recordAnswer(
                property,
                visit: person,
                source: person.operationalNotes.joined(separator: " "),
                carried: AssistantSelection(
                    visitIDs: [person.id],
                    personID: person.id,
                    lastKind: .taskDetail,
                    property: property
                )
            )
        }

        return taskPropertyReadout(property, among: candidates, asked: asked)
    }

    /// "Show Ivor's walking task" \u{2014} one task, named by its person and its kind.
    private func namedTaskLookup(_ asked: String) -> LocalAnswer? {
        guard matches(#"^\s*(show|actually)\b"#, asked),
              let match = AssistantPeople.recognise(asked, in: round.visits),
              case .one(let visit) = match,
              let concept = AssistantConcepts.resolve(asked) else { return nil }

        let found = visit.tasks
            .filter { matches(concept.label, $0.title) }
            .map { TaskMatch(visit: visit, task: $0) }
        guard !found.isEmpty else { return nil }

        if let property = AssistantTaskProperties.read(asked), property.isDetail {
            return taskPropertyReadout(property, among: found, asked: asked)
        }

        guard found.count == 1, let only = found.first else {
            return LocalAnswer(
                text: "Which task do you mean \u{2014} \(listTasks(found, join: "or"))?",
                kind: .clarify,
                selection: selection(for: found)
            )
        }

        return LocalAnswer(
            text: "\(only.visit.clientName) \u{2014} \(only.task.title) (\(only.task.isComplete ? "checked" : "unchecked")).",
            kind: .taskDetail,
            selection: selection(for: [only])
        )
    }

    /// A bare property question, which only means something after a list.
    private func bareProperty(_ asked: String) -> Bool {
        matches(#"^\s*(and |so )?(how long|how many times|what dose|what dressing type|what medication name|what model|what contact number|what instructions)\b"#, asked)
    }

    /// The rest of one person's checklist, other than the tasks just discussed.
    private func otherTasks(of visit: Visit, excluding discussed: [TaskMatch]) -> LocalAnswer? {
        let excluded = Set(discussed.filter { $0.visit.id == visit.id }.map(\.task.id))
        let others = visit.tasks.filter { !excluded.contains($0.id) }

        guard !others.isEmpty else {
            return LocalAnswer(
                text: "\(visit.clientName) has no other tasks recorded.",
                kind: .tasks,
                selection: AssistantSelection(visitIDs: [visit.id], personID: visit.id, lastKind: .tasks)
            )
        }

        let listed = others.map { "\($0.title)\($0.isComplete ? " (done)" : "")" }
        return LocalAnswer(
            text: "\(visit.clientName) has \(AssistantPhrasing.plural(others.count, "other task")): \(AssistantPhrasing.list(listed)).",
            kind: .tasks,
            selection: AssistantSelection(
                visitIDs: [visit.id],
                taskIDs: others.map(\.id),
                personID: visit.id,
                lastKind: .tasks
            )
        )
    }

    /// "Was there an additional note?" — the field the last answer read, asked
    /// about again without naming the person.
    private func carriedField(_ asked: String, visit: Visit) -> LocalAnswer? {
        if matches(#"\b(additional note|cancellation note)\b"#, asked)
            || (context?.field == .cancellation && matches(#"\bnotes?\b"#, asked) && !matches(#"\boperational\b"#, asked)) {
            let note = visit.cancellation?.note
            return LocalAnswer(
                text: note?.isEmpty == false
                    ? "\(visit.clientName)\u{2019}s additional cancellation note: \(note ?? "")"
                    : "No additional cancellation note was recorded for \(visit.clientName).",
                kind: .cancellation,
                selection: AssistantSelection(
                    visitIDs: [visit.id],
                    personID: visit.id,
                    lastKind: .cancellation,
                    field: .cancellation
                )
            )
        }

        if matches(#"\boperational notes?\b"#, asked) {
            return LocalAnswer(
                text: "\(visit.clientName)\u{2019}s operational notes: \(visit.operationalNotes.isEmpty ? "None recorded." : visit.operationalNotes.joined(separator: "; "))",
                kind: .notes,
                selection: AssistantSelection(
                    visitIDs: [visit.id],
                    personID: visit.id,
                    lastKind: .notes,
                    field: .operationalNote
                )
            )
        }

        if matches(#"\btravel (?:time|estimate)\b|\bhow long.*travel\b"#, asked) {
            return LocalAnswer(
                text: "\(visit.clientName)\u{2019}s recorded travel estimate is \(AssistantPhrasing.minutes(visit.location.travelMinutes)). This is separate from the visit duration; no live route has been recalculated.",
                kind: .travel,
                selection: AssistantSelection(
                    visitIDs: [visit.id],
                    personID: visit.id,
                    lastKind: .travel,
                    field: .travel
                )
            )
        }

        return nil
    }

    /// A property question about the tasks the last answer named, including an
    /// ordinal that picks one out of the list just read.
    private func taskPropertyAnswer(_ asked: String, among named: [TaskMatch]) -> LocalAnswer? {
        var candidates = named

        if let range = asked.range(
            of: #"\b(?:the )?(first|second|third|fourth|fifth)\s+task\b"#,
            options: [.regularExpression, .caseInsensitive]
        ) {
            let ordinals = ["first": 0, "second": 1, "third": 2, "fourth": 3, "fifth": 4]
            let word = asked[range].lowercased()
            guard let position = ordinals.first(where: { word.contains($0.key) })?.value else { return nil }
            guard position < candidates.count else {
                return LocalAnswer(
                    text: "There is no task at that position. Which of those tasks did you mean?",
                    kind: .clarify,
                    selection: context
                )
            }
            candidates = [candidates[position]]
        }

        guard let property = AssistantTaskProperties.read(asked) else {
            // An ordinal with no property reads the task back as it stands.
            guard candidates.count == 1, candidates.count < named.count else { return nil }
            let match = candidates[0]
            return LocalAnswer(
                text: "\(match.visit.clientName) \u{2014} \(match.task.title) (\(match.task.isComplete ? "checked" : "unchecked")).",
                kind: .taskDetail,
                selection: selection(for: candidates)
            )
        }

        return taskPropertyReadout(property, among: candidates, asked: asked)
    }

    // MARK: - Counts and progress

    private func counting(_ asked: String) -> LocalAnswer? {
        let progress = round.progress

        if matches(#"\b(how many|how much)\b"#, asked) || matches(#"^(count|total)\b"#, asked) {
            if matches(#"\btask"#, asked) { return nil }

            if matches(#"\b(left|remain|remaining|outstanding|still|more)\b"#, asked) {
                return LocalAnswer(
                    text: "\(AssistantPhrasing.plural(progress.remaining, "visit")) remain on today\u{2019}s round.",
                    kind: .remaining,
                    selection: AssistantSelection(visitIDs: AssistantQueries.remaining(round.visits).map(\.id))
                )
            }
            if matches(#"\bcancelled\b"#, asked) {
                let cancelled = AssistantQueries.byStatus(round.visits, .cancelled)
                return LocalAnswer(
                    text: cancelled.isEmpty
                        ? "No visit on today\u{2019}s round is cancelled."
                        : "\(AssistantPhrasing.plural(cancelled.count, "visit")) cancelled: \(AssistantPhrasing.names(cancelled)).",
                    kind: .counts,
                    selection: AssistantSelection(visitIDs: cancelled.map(\.id))
                )
            }
            if matches(#"\b(complete|completed|finished|done)\b"#, asked) {
                return LocalAnswer(
                    text: "\(progress.completed) of \(progress.total) visits are complete.",
                    kind: .counts,
                    selection: AssistantSelection(visitIDs: AssistantQueries.byStatus(round.visits, .completed).map(\.id))
                )
            }
            if matches(#"\bplanned\b"#, asked) {
                let planned = AssistantQueries.byStatus(round.visits, .planned)
                return LocalAnswer(
                    text: "\(AssistantPhrasing.plural(planned.count, "visit")) planned.",
                    kind: .counts,
                    selection: AssistantSelection(visitIDs: planned.map(\.id))
                )
            }
            if matches(#"\bvisit"#, asked) {
                return LocalAnswer(
                    text: "\(AssistantPhrasing.plural(progress.total, "visit")) on today\u{2019}s round: \(progress.summary).",
                    kind: .counts,
                    selection: AssistantSelection(visitIDs: round.ordered.map(\.id))
                )
            }
        }

        if matches(#"\b(progress|how (am i|is it) (doing|going)|how far)\b"#, asked) {
            return LocalAnswer(text: progress.summary + ".", kind: .counts)
        }

        return nil
    }

    // MARK: - Active and next

    private func activeOrNext(_ asked: String) -> LocalAnswer? {
        let wantsActive = matches(#"\b(active|ongoing|in progress|current|currently|on site|right now)\b"#, asked)
        let wantsNext = matches(#"\b(next|upcoming|after this|following|coming up)\b"#, asked)
            || matches(#"\bwho should i (go to|see|visit)\b|\bwhere am i going\b"#, asked)

        guard wantsActive || wantsNext else { return nil }

        if wantsActive {
            guard let active = round.active else {
                return LocalAnswer(
                    text: "No visit is active. \(nextSentence())",
                    kind: .active,
                    selection: round.upNext.map { AssistantSelection(visitIDs: [$0.id], personID: $0.id) }
                )
            }
            return LocalAnswer(
                text: "\(active.clientName) is your current active visit, at \(AssistantPhrasing.window(active)) (\(active.status.title)).",
                kind: .active,
                selection: AssistantSelection(visitIDs: [active.id], personID: active.id)
            )
        }

        guard let next = round.upNext else {
            return LocalAnswer(text: "Nothing is left waiting on today\u{2019}s round.", kind: .next)
        }
        return LocalAnswer(
            text: nextSentence(),
            kind: .next,
            selection: AssistantSelection(visitIDs: [next.id], personID: next.id)
        )
    }

    private func nextSentence() -> String {
        guard let next = round.upNext else { return "Nothing is left waiting on today\u{2019}s round." }
        if next.status.isInProgress {
            return "\(next.clientName) is your current active visit, at \(AssistantPhrasing.window(next)) (\(next.status.title))."
        }
        return "\(next.clientName) is next, at \(AssistantPhrasing.window(next)) — \(next.visitType), \(next.location.singleLineAddress)."
    }

    // MARK: - Status listings

    private func statusListing(_ asked: String) -> LocalAnswer? {
        guard matches(#"\b(which|what|who|show|list|any)\b"#, asked)
            || matches(#"^(planned|completed|cancelled)\b"#, asked) else {
            return nil
        }

        // A question about checklists belongs to the task family, even when it
        // uses a word that also names a visit status.
        if matches(#"\b(task|tasks|checklist)\b"#, asked) { return nil }

        let statuses: [(VisitStatus, String)] = [
            (.cancelled, #"\bcancel"#),
            (.completed, #"\b(completed|finished|done)\b"#),
            (.enRoute, #"\ben ?route\b"#),
            (.arrived, #"\barrived\b"#),
            (.planned, #"\bplanned\b"#)
        ]

        for (status, pattern) in statuses where matches(pattern, asked) {
            // A question about how cancelling works is guidance, not a listing.
            if status == .cancelled && matches(#"\b(how|why can|can i|what happens)\b"#, asked) { return nil }

            let found = AssistantQueries.byStatus(round.visits, status)
            guard !found.isEmpty else {
                return LocalAnswer(
                    text: "No visit on today\u{2019}s round is \(status.title.lowercased()).",
                    kind: .statusList
                )
            }

            let described = found.map { "\($0.clientName) (\(AssistantPhrasing.window($0)))" }
            return LocalAnswer(
                text: "\(AssistantPhrasing.plural(found.count, "visit")) \(status.title.lowercased()): \(AssistantPhrasing.list(described)).",
                kind: .statusList,
                selection: AssistantSelection(
                    visitIDs: found.map(\.id),
                    lastKind: .statusList,
                    query: SelectionQuery(subject: .visits, operation: .list, statuses: [status])
                )
            )
        }

        return nil
    }

    private func priorityQuestion(_ asked: String) -> LocalAnswer? {
        guard matches(#"\bpriorit"#, asked) else { return nil }

        let found = AssistantQueries.priority(round.visits)
        guard !found.isEmpty else {
            return LocalAnswer(text: "No visit on today\u{2019}s round is marked Priority.", kind: .priority)
        }

        let described = found.map { "\($0.clientName) — \($0.visitType), \(AssistantPhrasing.window($0)) (\($0.status.title))" }
        return LocalAnswer(
            text: "\(AssistantPhrasing.plural(found.count, "visit")) marked Priority: \(AssistantPhrasing.list(described)).",
            kind: .priority,
            selection: AssistantSelection(visitIDs: found.map(\.id))
        )
    }

    // MARK: - Notes

    private func noteQuestion(_ asked: String) -> LocalAnswer? {
        guard matches(#"\bnotes?\b"#, asked) else { return nil }

        var carried: Visit?
        if let match = AssistantPeople.recognise(asked, in: round.visits), case .one(let visit) = match {
            carried = visit
        } else if matches(#"\boperational notes?\b"#, asked) {
            carried = context?.personID.flatMap { round.visit(id: $0) }
        }

        if let visit = carried {
            guard !visit.operationalNotes.isEmpty else {
                return LocalAnswer(
                    text: "\(visit.clientName)\u{2019}s visit records no operational notes.",
                    kind: .notes,
                    selection: AssistantSelection(
                        visitIDs: [visit.id],
                        personID: visit.id,
                        lastKind: .notes,
                        field: .operationalNote
                    )
                )
            }
            return LocalAnswer(
                text: "\(visit.clientName): \(visit.operationalNotes.joined(separator: " "))",
                kind: .notes,
                selection: AssistantSelection(
                    visitIDs: [visit.id],
                    personID: visit.id,
                    lastKind: .notes,
                    field: .operationalNote
                )
            )
        }

        let withNotes = AssistantQueries.withNotes(round.visits)
        guard !withNotes.isEmpty else {
            return LocalAnswer(text: "No visit on today\u{2019}s round records an operational note.", kind: .notes)
        }

        let described = withNotes.map { "\($0.clientName) — \($0.operationalNotes.joined(separator: " "))" }
        return LocalAnswer(
            text: "\(AssistantPhrasing.plural(withNotes.count, "visit")) record notes: \(described.joined(separator: "; ")).",
            kind: .notes,
            selection: AssistantSelection(visitIDs: withNotes.map(\.id))
        )
    }

    // MARK: - Tasks

    private func taskQuestion(_ asked: String) -> LocalAnswer? {
        // A concept the round knows about is reason enough to search the
        // checklists, even when the question never says the word "task".
        guard matches(#"\b(task|tasks|checklist|check ?list)\b"#, asked)
            || isConceptSearch(asked)
            || AssistantConcepts.resolve(asked) != nil else { return nil }

        let person = AssistantPeople.recognise(asked, in: round.visits)

        if case .ambiguous(let candidates) = person {
            return LocalAnswer(
                text: "More than one person on the round matches that. Did you mean \(AssistantPhrasing.names(candidates))?",
                kind: .ambiguous
            )
        }
        if case .unknown(let name) = person {
            return LocalAnswer(text: AssistantCopy.notFoundPerson(name), kind: .notFound)
        }

        // One person's checklist.
        if case .one(let visit) = person {
            let summary = AssistantQueries.taskSummary(visit)

            if matches(#"\b(remain|remaining|outstanding|left|unticked|unchecked|still)\b"#, asked) {
                guard !summary.remaining.isEmpty else {
                    return LocalAnswer(
                        text: "\(visit.clientName) has no outstanding tasks: \(summary.total) of \(summary.total) are ticked.",
                        kind: .tasks,
                        selection: AssistantSelection(visitIDs: [visit.id], personID: visit.id)
                    )
                }
                return LocalAnswer(
                    text: "\(visit.clientName) has \(AssistantPhrasing.plural(summary.remaining.count, "task")) outstanding: \(AssistantPhrasing.list(summary.remaining.map(\.title))).",
                    kind: .tasks,
                    selection: AssistantSelection(
                        visitIDs: [visit.id],
                        taskIDs: summary.remaining.map(\.id),
                        personID: visit.id,
                        lastKind: .tasks
                    )
                )
            }

            if matches(#"\bhow many\b"#, asked) {
                return LocalAnswer(
                    text: "\(AssistantPhrasing.plural(summary.total, "task")) — \(visit.clientName) has \(summary.done.count) ticked and \(summary.remaining.count) unticked.",
                    kind: .taskCount,
                    selection: AssistantSelection(visitIDs: [visit.id], personID: visit.id, lastKind: .taskCount)
                )
            }

            let described = visit.tasks.map { "\($0.title) (\($0.isComplete ? "done" : "unchecked"))" }
            return LocalAnswer(
                text: "\(visit.clientName): \(summary.done.count) of \(summary.total) done. \(AssistantPhrasing.list(described)).",
                kind: .tasks,
                selection: AssistantSelection(
                    visitIDs: [visit.id],
                    taskIDs: visit.tasks.map(\.id),
                    personID: visit.id,
                    lastKind: .tasks
                )
            )
        }

        // Totals across the round.
        if matches(#"\bhow many\b"#, asked) && !isConceptSearch(asked) {
            let totals = AssistantQueries.taskTotals(round.visits)

            func counted(_ query: SelectionQuery) -> AssistantSelection {
                var selection = AssistantSelection(lastKind: .taskTotals)
                selection.query = query
                return selection
            }

            let base = SelectionQuery(subject: .tasks, operation: .count)

            if matches(#"\b(due|remain|remaining|outstanding|left|still)\b"#, asked) {
                var query = base
                query.actionable = true
                query.done = false
                return LocalAnswer(
                    text: "\(AssistantPhrasing.plural(totals.due, "task")) still due on visits that are not yet resolved.",
                    kind: .taskTotals,
                    selection: counted(query)
                )
            }
            if matches(#"\b(unticked|unchecked)\b"#, asked) {
                var query = base
                query.done = false
                return LocalAnswer(
                    text: "\(AssistantPhrasing.plural(totals.outstanding, "task")) are unchecked across the round, including closed visits.",
                    kind: .taskTotals,
                    selection: counted(query)
                )
            }
            return LocalAnswer(
                text: "\(AssistantPhrasing.plural(totals.total, "task")) recorded across the selected visits.",
                kind: .taskTotals,
                selection: counted(base)
            )
        }

        // A search across every checklist.
        let result = AssistantQueries.matchTasks(round.visits, phrase: asked)
        guard !result.matches.isEmpty else {
            // Nothing literal. A broader concept is the last honest reading
            // before reporting no match at all.
            if let broad = AssistantConcepts.resolve(asked) {
                return conceptAnswer(broad)
            }
            return LocalAnswer(
                text: "No task on today\u{2019}s round matches that.",
                kind: .taskSearch
            )
        }

        let described = result.matches.map(AssistantPhrasing.describe)
        let visits = result.visits
        return LocalAnswer(
            text: "\(AssistantPhrasing.plural(visits.count, "visit")) \(visits.count == 1 ? "has" : "have") a matching task: \(described.joined(separator: "; ")).",
            kind: .taskSearch,
            selection: AssistantSelection(
                visitIDs: visits.map(\.id),
                taskIDs: result.matches.map(\.task.id),
                personID: visits.count == 1 ? visits[0].id : nil,
                lastKind: .taskSearch
            )
        )
    }

    /// Whether the question is searching checklists by an activity word rather
    /// than asking about tasks in general.
    private func isConceptSearch(_ asked: String) -> Bool {
        matches(#"\b(wound|dressing|medication|medicine|walk|walking|wash|washing|bathe|meal|breakfast|lunch|food|exercise|exercises|mobility|hygiene|alarm|prescription|bin|clothes)\b"#, asked)
    }

    // MARK: - Schedule

    private func scheduleQuestion(_ asked: String) -> LocalAnswer? {
        guard matches(#"\b(time|when|start|finish|end|schedule|shift|long|duration|travel|longest|shortest|whole|entire)\b"#, asked) else { return nil }

        // "What is the longest visit?" \u{2014} an extreme of the recorded slots.
        if matches(#"\b(longest|shortest)\b"#, asked) {
            let extremes = AssistantQueries.durationExtremes(round.visits)
            let wantsShortest = matches(#"\bshortest\b"#, asked)
            guard let pick = wantsShortest ? extremes.shortest : extremes.longest else {
                return LocalAnswer(text: "There are no visits on this round.", kind: .duration)
            }
            return LocalAnswer(
                text: "The \(wantsShortest ? "shortest" : "longest") visit of the round is \(pick.clientName), scheduled for \(AssistantPhrasing.minutes(AssistantQueries.durationMinutes(pick))), from \(AssistantPhrasing.window(pick)).",
                kind: .duration,
                selection: AssistantSelection(
                    visitIDs: [pick.id],
                    personID: pick.id,
                    lastKind: .duration,
                    property: .duration
                )
            )
        }

        if matches(#"\b(shift|finished by|finish by|end of (the )?(day|shift))\b"#, asked) {
            return LocalAnswer(
                text: "The shift runs \(round.shiftWindow) on \(round.round).",
                kind: .schedule
            )
        }

        if let match = AssistantPeople.recognise(asked, in: round.visits), case .one(let visit) = match {
            if matches(#"\btravel\b"#, asked) {
                guard visit.location.travelMinutes > 0 else {
                    return LocalAnswer(
                        text: "\(visit.clientName)\u{2019}s visit records no travel estimate.",
                        kind: .travel,
                        selection: AssistantSelection(visitIDs: [visit.id], personID: visit.id)
                    )
                }
                return LocalAnswer(
                    text: "\(visit.clientName)\u{2019}s visit records \(AssistantPhrasing.minutes(visit.location.travelMinutes)) of travel from the previous call.",
                    kind: .travel,
                    selection: AssistantSelection(visitIDs: [visit.id], personID: visit.id)
                )
            }
            if matches(#"\b(how long|duration)\b"#, asked) {
                return LocalAnswer(
                    text: "\(visit.clientName)\u{2019}s visit is scheduled for \(AssistantPhrasing.minutes(AssistantQueries.durationMinutes(visit))), from \(AssistantPhrasing.window(visit)).",
                    kind: .duration,
                    selection: AssistantSelection(visitIDs: [visit.id], personID: visit.id)
                )
            }
            return LocalAnswer(
                text: "\(visit.clientName)\u{2019}s visit is scheduled \(AssistantPhrasing.window(visit)) (\(visit.status.title)).",
                kind: .schedule,
                selection: AssistantSelection(visitIDs: [visit.id], personID: visit.id)
            )
        }

        if matches(#"\b(whole|entire) visit\b"#, asked)
            || (matches(#"how long.*\bvisit\b|\bvisit\b.*how long"#, asked)
                && AssistantPeople.recognise(asked, in: round.visits) == nil) {
            if let carried = context?.personID.flatMap({ round.visit(id: $0) }) {
                return LocalAnswer(
                    text: "\(carried.clientName)\u{2019}s whole visit is scheduled for \(AssistantPhrasing.minutes(AssistantQueries.durationMinutes(carried))), from \(AssistantPhrasing.window(carried)) (\(carried.status.title)).",
                    kind: .duration,
                    selection: AssistantSelection(
                        visitIDs: [carried.id],
                        personID: carried.id,
                        lastKind: .duration,
                        property: .duration
                    )
                )
            }
            return LocalAnswer(
                text: "Which visit did you mean?",
                kind: .clarify,
                selection: AssistantSelection(pending: .duration)
            )
        }

        if matches(#"\b(last|final)\b"#, asked) {
            guard let last = round.ordered.last else { return nil }
            return LocalAnswer(
                text: "\(last.clientName) is the last visit scheduled, at \(AssistantPhrasing.window(last)) (\(last.status.title)).",
                kind: .schedule,
                selection: AssistantSelection(visitIDs: [last.id], personID: last.id)
            )
        }

        if matches(#"\bfirst\b"#, asked) {
            guard let first = round.ordered.first else { return nil }
            return LocalAnswer(
                text: "\(first.clientName) is the first visit scheduled, at \(AssistantPhrasing.window(first)) (\(first.status.title)).",
                kind: .schedule,
                selection: AssistantSelection(visitIDs: [first.id], personID: first.id)
            )
        }

        return nil
    }

    // MARK: - Completion history

    private func completionHistory(_ asked: String) -> LocalAnswer? {
        guard matches(#"\b(just (finish|finished|completed)|last (visit|one) (i|we) (did|completed|finished)|which visit did i)\b"#, asked)
                || matches(#"\bwho was my last visit\b"#, asked)
                // "Who did I finish last?" asks about observed order too, and
                // must not be answered with a schedule position.
                || matches(#"\b(finish|finished|complete|completed)\s+last\b"#, asked)
                || matches(#"\b(who|which|what)\b[^?]*\bdid (i|we)\b[^?]*\b(finish|finished|complete|completed|visit|see|saw)\b"#, asked) else {
            return nil
        }

        if let latest = round.sessionCompletions.last {
            return LocalAnswer(
                text: "\(latest.clientName) is the visit you completed most recently this session, scheduled \(AssistantPhrasing.window(latest)) (Completed).",
                kind: .completion,
                selection: AssistantSelection(visitIDs: [latest.id], personID: latest.id)
            )
        }

        // The visits that begin the round already Completed carry no observed
        // order, so a schedule position is offered as exactly that.
        let completed = AssistantQueries.byStatus(round.visits, .completed)
        guard let last = completed.last else {
            return LocalAnswer(text: "No visit on today\u{2019}s round is completed yet.", kind: .completion)
        }

        return LocalAnswer(
            text: "\(last.clientName) is the latest scheduled visit marked Completed; the initial records do not say which was completed last; scheduled \(AssistantPhrasing.window(last)) (Completed).",
            kind: .completion,
            selection: AssistantSelection(visitIDs: [last.id], personID: last.id)
        )
    }

    // MARK: - Cancellation record

    private func cancellationRecord(_ asked: String) -> LocalAnswer? {
        guard matches(#"\b(why|reason|note)\b"#, asked), matches(#"\bcancel"#, asked) else { return nil }

        // Asking which reasons the app offers is a question about the control.
        if matches(#"\b(can i give|are there|what reasons|which reasons|options|choose from)\b"#, asked) {
            return nil
        }

        var named: Visit?
        if let match = AssistantPeople.recognise(asked, in: round.visits), case .one(let visit) = match {
            named = visit
        } else if matches(#"\b(that|those|it|they|them|this|her|his|their)\b"#, asked) {
            named = context?.personID.flatMap { round.visit(id: $0) }
        }

        guard let visit = named else {
            let cancelled = AssistantQueries.byStatus(round.visits, .cancelled)
            guard !cancelled.isEmpty else {
                return LocalAnswer(text: "No visit on today\u{2019}s round is cancelled.", kind: .cancellation)
            }
            let described = cancelled.map { visit -> String in
                guard let cancellation = visit.cancellation else { return visit.clientName }
                return "\(visit.clientName) — \(cancellation.reason.title)"
            }
            return LocalAnswer(
                text: "\(AssistantPhrasing.plural(cancelled.count, "visit")) cancelled: \(described.joined(separator: "; ")).",
                kind: .cancellation,
                selection: AssistantSelection(visitIDs: cancelled.map(\.id))
            )
        }

        guard let cancellation = visit.cancellation else {
            return LocalAnswer(
                text: "\(visit.clientName)\u{2019}s visit is \(visit.status.title) and records no cancellation.",
                kind: .cancellation,
                selection: AssistantSelection(
                    visitIDs: [visit.id],
                    personID: visit.id,
                    lastKind: .cancellation,
                    field: .cancellation
                )
            )
        }

        // Reason and note are separate fields and are reported separately.
        var text = "\(visit.clientName)\u{2019}s visit was cancelled. Reason: \(cancellation.reason.title)."
        if !cancellation.note.isEmpty {
            text += " Note: \(cancellation.note)."
        }

        return LocalAnswer(
            text: text,
            kind: .cancellation,
            selection: AssistantSelection(
                visitIDs: [visit.id],
                personID: visit.id,
                lastKind: .cancellation,
                field: .cancellation
            )
        )
    }

    // MARK: - One person

    private func personQuestion(_ asked: String) -> LocalAnswer? {
        guard let match = AssistantPeople.recognise(asked, in: round.visits) else { return nil }

        switch match {
        case .ambiguous(let candidates):
            return LocalAnswer(
                text: "More than one person on the round matches that. Did you mean \(AssistantPhrasing.names(candidates))?",
                kind: .ambiguous
            )
        case .unknown(let name):
            return LocalAnswer(text: AssistantCopy.notFoundPerson(name), kind: .notFound)
        case .one(let visit):
            if let facts = personFacts(asked, visit: visit) { return facts }

            let summary = AssistantQueries.taskSummary(visit)
            var text = "\(visit.clientName) — \(visit.visitType), \(AssistantPhrasing.window(visit)) (\(visit.status.title)). "
            text += "\(visit.location.singleLineAddress). \(summary.done.count) of \(summary.total) tasks done."
            if visit.priority == .priority { text += " Marked Priority." }

            return LocalAnswer(
                text: text,
                kind: .person,
                selection: AssistantSelection(visitIDs: [visit.id], personID: visit.id, lastKind: .person)
            )
        }
    }

    /// A single recorded field about one person.
    private func personFacts(_ asked: String, visit: Visit) -> LocalAnswer? {
        // "\u{2026} and what time is their visit?" \u{2014} the slot as recorded, and no
        // inference about where the practitioner is in it.
        if matches(#"\b(time|when|scheduled|slot)\b"#, asked) {
            return LocalAnswer(
                text: "\(visit.clientName)\u{2019}s visit is scheduled \(AssistantPhrasing.window(visit)) (\(visit.status.title)).",
                kind: .schedule,
                selection: AssistantSelection(visitIDs: [visit.id], personID: visit.id)
            )
        }
        if matches(#"\b(address|where|location|postcode)\b"#, asked) {
            return LocalAnswer(
                text: "\(visit.clientName)\u{2019}s visit is at \(visit.location.singleLineAddress).",
                kind: .person,
                selection: AssistantSelection(visitIDs: [visit.id], personID: visit.id)
            )
        }
        if matches(#"\b(status|state)\b"#, asked) {
            return LocalAnswer(
                text: "\(visit.clientName)\u{2019}s visit is \(visit.status.title).",
                kind: .person,
                selection: AssistantSelection(visitIDs: [visit.id], personID: visit.id)
            )
        }
        if matches(#"\b(service|type|kind of visit)\b"#, asked) {
            return LocalAnswer(
                text: "\(visit.clientName)\u{2019}s visit is \(visit.visitType).",
                kind: .person,
                selection: AssistantSelection(visitIDs: [visit.id], personID: visit.id)
            )
        }
        if matches(#"\breference\b"#, asked) {
            return LocalAnswer(
                text: "\(visit.clientName)\u{2019}s visit reference is \(visit.reference).",
                kind: .person,
                selection: AssistantSelection(visitIDs: [visit.id], personID: visit.id)
            )
        }
        return nil
    }

    // MARK: - Recorded task properties

    private func task(id: VisitTask.ID) -> TaskMatch? {
        for visit in round.visits {
            if let task = visit.tasks.first(where: { $0.id == id }) {
                return TaskMatch(visit: visit, task: task)
            }
        }
        return nil
    }

    /// "\u{2018}A\u{2019}, \u{2018}B\u{2019} or \u{2018}C\u{2019}", each named by its owner when more than one
    /// person is listed.
    private func listTasks(_ matches: [TaskMatch], join: String) -> String {
        let onePerson = Set(matches.map(\.visit.id)).count == 1
        let labels = matches.map { match in
            onePerson
                ? "\u{2018}\(match.task.title)\u{2019}"
                : "\(match.visit.clientName)\u{2019}s \u{2018}\(match.task.title)\u{2019}"
        }
        guard labels.count > 1 else { return labels.joined() }
        return "\(labels.dropLast().joined(separator: ", ")) \(join) \(labels[labels.count - 1])"
    }

    func selection(for matches: [TaskMatch], property: TaskProperty? = nil) -> AssistantSelection {
        var visitIDs: [Visit.ID] = []
        for match in matches where !visitIDs.contains(match.visit.id) {
            visitIDs.append(match.visit.id)
        }

        return AssistantSelection(
            visitIDs: visitIDs,
            taskIDs: matches.map(\.task.id),
            personID: visitIDs.count == 1 ? visitIDs.first : nil,
            lastKind: .taskDetail,
            property: property
        )
    }

    /// Answers a property question about a set of tasks.
    ///
    /// When several were named, the reader is asked which only if choosing
    /// could change the answer. If not one of them records what was asked for,
    /// saying so is both honest and shorter than a question nobody needs to
    /// answer.
    func taskPropertyReadout(
        _ property: TaskProperty,
        among candidates: [TaskMatch],
        asked: String = ""
    ) -> LocalAnswer {
        var matches = candidates

        // The task whose wording uses a word the reader typed, when that leaves
        // fewer than were named. General, and knows nothing of any one concept.
        if matches.count > 1, !asked.isEmpty {
            let spoken = Set(AssistantQueries.searchWords(asked))
            let named = matches.filter {
                !Set(AssistantQueries.searchWords(AssistantTaskProperties.source($0.task)))
                    .isDisjoint(with: spoken)
            }
            if !named.isEmpty, named.count < matches.count { matches = named }
        }

        guard matches.count > 1 else {
            guard let match = matches.first else {
                return LocalAnswer(text: "Which task do you mean?", kind: .clarify, selection: context)
            }
            return singleTaskAnswer(property, for: match, asked: asked)
        }

        // Several tasks on one person, for a property the round records against
        // the person rather than against any single task.
        let recordLevel: [TaskProperty] = [.medicationName, .dose, .equipmentModel, .contactNumber]
        if matches.count > 1,
           Set(matches.map(\.visit.id)).count == 1,
           recordLevel.contains(property) {
            return recordAnswer(
                property,
                visit: matches[0].visit,
                source: matches.map { AssistantTaskProperties.source($0.task) }.joined(separator: "; "),
                carried: selection(for: matches, property: property)
            )
        }

        // Still several. If not one of them records the property, the answer is
        // available without making the reader choose.
        if property.isDetail, matches.allSatisfy({ recordedValue(property, in: $0.task) == nil }) {
            let people = Set(matches.map(\.visit.clientName))
            let whose = people.count == 1
                ? "\(matches[0].visit.clientName)\u{2019}s matching tasks"
                : "those tasks"
            return LocalAnswer(
                text: "None of \(whose) records \(property.withArticle). They are \(listTasks(matches, join: "and")).",
                kind: .taskDetail,
                selection: selection(for: matches, property: property)
            )
        }

        // Naming the candidates, so "which task do you mean?" can be answered.
        return LocalAnswer(
            text: "Which task do you mean \u{2014} \(listTasks(matches, join: "or"))?",
            kind: .clarify,
            selection: selection(for: matches, property: property)
        )
    }

    /// What a task records for a property, or `nil` when it records none.
    private func recordedValue(_ property: TaskProperty, in task: VisitTask) -> String? {
        switch property {
        case .completion: task.isComplete ? "ticked" : "unchecked"
        case .hint: task.detail
        default: AssistantTaskProperties.value(of: property, in: AssistantTaskProperties.source(task))
        }
    }

    private func singleTaskAnswer(
        _ property: TaskProperty,
        for pair: TaskMatch,
        asked: String = ""
    ) -> LocalAnswer {
        let named = "\(pair.visit.clientName)\u{2019}s \u{2018}\(pair.task.title)\u{2019} task"
        let carried = selection(for: [pair], property: property)

        switch property {
        case .completion:
            // Read from the round every time, never from the previous reply.
            let wantsUnchecked = AssistantTaskProperties.asksUnchecked(asked)
            let holds = wantsUnchecked ? !pair.task.isComplete : pair.task.isComplete
            let state = pair.task.isComplete ? "ticked" : "unchecked"
            return LocalAnswer(
                text: "\(holds ? "Yes." : "No.") \(named) is \(state).",
                kind: .taskDetail,
                selection: carried
            )

        case .hint:
            return LocalAnswer(
                text: pair.task.detail.map { "\(named) records a task hint: \($0)." }
                    ?? "\(named) does not record a task hint.",
                kind: .taskDetail,
                selection: carried
            )

        case .repetitions:
            guard let value = recordedValue(property, in: pair.task) else {
                return LocalAnswer(
                    text: "\(named) does not specify repetitions.",
                    kind: .taskDetail,
                    selection: carried
                )
            }
            return LocalAnswer(
                text: "\(named) records repetitions: \(value).",
                kind: .taskDetail,
                selection: carried
            )

        case .duration:
            guard let value = recordedValue(property, in: pair.task) else {
                return LocalAnswer(
                    text: "\(named) does not specify a duration. It only lists \u{2018}\(pair.task.title)\u{2019}.",
                    kind: .taskDetail,
                    selection: carried
                )
            }
            return LocalAnswer(
                text: "\(named) records duration: \(value).",
                kind: .taskDetail,
                selection: carried
            )

        default:
            // A recorded detail, read back exactly as the round wrote it down.
            // Nothing here supplies a value the record does not hold.
            guard let value = recordedValue(property, in: pair.task) else {
                return LocalAnswer(
                    text: "\(pair.visit.clientName)\u{2019}s record does not specify \(property.withArticle). It only lists \u{2018}\(pair.task.title)\u{2019}.",
                    kind: .taskDetail,
                    selection: carried
                )
            }
            return LocalAnswer(
                text: "\(named) records \(property.rawValue): \(value).",
                kind: .taskDetail,
                selection: carried
            )
        }
    }

    /// A property recorded against a person's record rather than against one
    /// task, read from every task that could have carried it.
    private func recordAnswer(
        _ property: TaskProperty,
        visit: Visit,
        source: String,
        carried: AssistantSelection
    ) -> LocalAnswer {
        guard let value = AssistantTaskProperties.value(of: property, in: source) else {
            return LocalAnswer(
                text: "\(visit.clientName)\u{2019}s record does not specify \(property.withArticle).",
                kind: .taskDetail,
                selection: carried
            )
        }
        return LocalAnswer(
            text: "\(visit.clientName)\u{2019}s record records \(property.rawValue): \(value).",
            kind: .taskDetail,
            selection: carried
        )
    }

    private func matches(_ pattern: String, _ text: String) -> Bool {
        text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }
}
