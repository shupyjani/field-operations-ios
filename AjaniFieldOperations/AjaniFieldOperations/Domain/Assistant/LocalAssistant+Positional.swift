import Foundation

/// Visits named by position rather than by person, and the questions that are
/// about the exchange or the clock rather than about the round.
nonisolated extension LocalAssistant {
    private func p(_ pattern: String, _ text: String) -> Bool {
        AssistantInterpreter.matches(pattern, text)
    }

    // MARK: - Conversation

    /// "What did I just ask?"
    ///
    /// Only the reader's own questions are in reach. Nothing else is held here
    /// to quote, and no instruction or configuration is readable from it.
    func conversationHistory(_ asked: String) -> LocalAnswer? {
        guard p(#"\bwhat did (i|we) (just )?(ask|say)\b"#, asked)
            || p(#"\bmy (last|previous|first|earlier) (question|message)\b"#, asked)
            || p(#"\brepeat (my|the) (last|previous) (question|message)\b"#, asked)
            || p(#"\b(last|previous|earlier) (question|message) (i|we)\b"#, asked) else { return nil }

        guard let previous = context?.previousQuestion, !previous.isEmpty else {
            return LocalAnswer(
                text: "That is the first question you have asked in this conversation, so there is no earlier one to repeat.",
                kind: .unsupported,
                selection: context
            )
        }

        return LocalAnswer(
            text: "Your previous question was: \u{201C}\(previous)\u{201D}",
            kind: .unsupported,
            selection: context
        )
    }

    // MARK: - The clock

    /// The app records scheduled times and nothing else, so a question about
    /// the current time is answered by saying exactly that.
    func clockQuestion(_ asked: String) -> LocalAnswer? {
        guard p(#"\bwhat('?s| is) the time\b|\bwhat time is it\b|\btime now\b|\bcurrent time\b"#, asked)
            || p(#"^what time[?.!]*$"#, asked) else { return nil }

        var text = "This app does not track a live current time. \(round.workerFirstName)\u{2019}s shift runs \(round.shiftWindow)."
        if let active = round.active {
            text += " \(active.clientName) is the active visit, at \(AssistantPhrasing.window(active))."
        } else if let next = round.upNext {
            text += " \(next.clientName) is next, at \(AssistantPhrasing.window(next))."
        }

        return LocalAnswer(text: text, kind: .schedule)
    }

    /// "How long have I been there?" — the round records no elapsed time.
    func elapsedTimeQuestion(_ asked: String) -> LocalAnswer? {
        guard p(#"\b(actual|elapsed|spent|since arriv|how long have)\b"#, asked) else { return nil }

        return LocalAnswer(
            text: "The records do not include actual elapsed time or arrival timestamps; only scheduled visit times are available.",
            kind: .duration
        )
    }

    /// "What time should all visits be completed by?" — the last visit's end is
    /// not the same as the end of the shift, and both are worth saying.
    func finishByQuestion(_ asked: String) -> LocalAnswer? {
        guard p(#"\b(completed|finished|done)\b"#, asked),
              p(#"\bby\b"#, asked),
              p(#"\btime\b"#, asked) else { return nil }

        guard let last = round.ordered.last else {
            return LocalAnswer(text: "The shift runs \(round.shiftWindow).", kind: .schedule)
        }

        return LocalAnswer(
            text: "The last visit of the round, \(last.clientName), is scheduled to end at \(VisitFormatting.time(last.scheduledEnd)). The shift itself runs \(round.shiftWindow).",
            kind: .schedule,
            selection: AssistantSelection(visitIDs: [last.id], personID: last.id, lastKind: .schedule)
        )
    }

    // MARK: - Runs of visits

    private static let counts: [String: Int] = [
        "one": 1, "two": 2, "three": 3, "four": 4, "five": 5,
        "six": 6, "seven": 7, "eight": 8, "nine": 9, "ten": 10
    ]

    /// "The first two visits", "my last three clients", "the next two".
    func scheduleRun(_ asked: String) -> LocalAnswer? {
        guard p(#"\b(visit|visits|client|clients|patient|patients|people)\b"#, asked),
              let range = asked.range(
                  of: #"\b(first|last|next)\s+(\d+|one|two|three|four|five|six|seven|eight|nine|ten)\b"#,
                  options: [.regularExpression, .caseInsensitive]
              ),
              !p(#"\btasks?\b"#, asked) else { return nil }

        let phrase = String(asked[range]).lowercased()
        let words = phrase.split(separator: " ").map(String.init)
        guard let kind = words.first, let amount = words.last else { return nil }
        guard let count = Int(amount) ?? Self.counts[amount], count > 0 else { return nil }

        let ordered = round.ordered
        let remaining = AssistantQueries.remaining(round.visits)

        let picked: [Visit]
        switch kind {
        case "first":
            picked = Array((p(#"\bremain|\bleft\b|\bstill\b"#, asked) ? remaining : ordered).prefix(count))
        case "last":
            picked = Array(ordered.suffix(count))
        default:
            let leading = round.active.map { active in [active] + remaining.filter { $0.id != active.id } } ?? remaining
            picked = Array(leading.prefix(count))
        }

        guard !picked.isEmpty else { return nil }
        let described = picked.map { "\($0.clientName) (\(AssistantPhrasing.window($0)))" }

        return LocalAnswer(
            text: "Your \(kind) \(AssistantPhrasing.plural(picked.count, "visit")): \(AssistantPhrasing.list(described)).",
            kind: .schedule,
            selection: AssistantSelection(visitIDs: picked.map(\.id), lastKind: .schedule)
        )
    }

    // MARK: - A visit named by position

    /// "Who comes after Halina?", "what tasks does the next visit have?"
    ///
    /// Returns `nil` for the plain "who is next?" family, which has its own
    /// answer and its own wording.
    func positionalQuestion(_ asked: String) -> LocalAnswer? {
        guard let (visit, lead) = positionalTarget(asked) else { return nil }

        let asksTasks = p(#"\btasks?\b|\bchecklist\b"#, asked)
        let asksLast = p(#"\b(last|final)\b"#, asked)
        guard asksTasks || asksLast || isNeighbour(asked) else { return nil }

        let carried = AssistantSelection(
            visitIDs: [visit.id],
            personID: visit.id,
            lastKind: asksTasks ? .tasks : .person
        )

        guard asksTasks else {
            return LocalAnswer(
                text: "\(lead) is \(AssistantPhrasing.describe(visit)).",
                kind: .person,
                selection: carried
            )
        }

        let summary = AssistantQueries.taskSummary(visit)

        if p(#"\bhow many\b"#, asked) {
            return LocalAnswer(
                text: "\(AssistantPhrasing.plural(summary.total, "task")) \u{2014} \(lead) is \(visit.clientName), with \(summary.done.count) ticked and \(summary.remaining.count) unticked.",
                kind: .taskCount,
                selection: carried
            )
        }

        let described = visit.tasks.map { "\($0.title) (\($0.isComplete ? "done" : "unchecked"))" }
        var listed = carried
        listed.taskIDs = visit.tasks.map(\.id)

        return LocalAnswer(
            text: "\(lead) is \(visit.clientName): \(summary.done.count) of \(summary.total) done. \(AssistantPhrasing.list(described)).",
            kind: .tasks,
            selection: listed
        )
    }

    private func isNeighbour(_ asked: String) -> Bool {
        neighbourAnchor(asked) != nil
    }

    /// The person a positional question is measured against, when it names one.
    private func neighbourAnchor(_ asked: String) -> (anchor: Visit, side: String)? {
        guard let range = asked.range(
            of: #"\b(before|after)\s+([a-z][a-z'\-]+)"#,
            options: [.regularExpression, .caseInsensitive]
        ) else { return nil }

        let phrase = String(asked[range])
        let words = phrase.split(separator: " ").map(String.init)
        guard words.count == 2 else { return nil }

        let excluded = ["noon", "midday", "visiting", "arrival", "arriving",
                        "the", "my", "this", "that", "a", "them", "it"]
        guard !excluded.contains(words[1].lowercased()),
              !p(#"\bafter (this|that|my|the)\b"#, asked) else { return nil }

        guard case .one(let anchor)? = AssistantPeople.recognise(words[1], in: round.visits) else {
            return nil
        }
        return (anchor, words[0].lowercased())
    }

    /// The visit a positional question points at, and how to introduce it.
    private func positionalTarget(_ asked: String) -> (visit: Visit, lead: String)? {
        if let (anchor, side) = neighbourAnchor(asked) {
            let ordered = round.ordered
            guard let index = ordered.firstIndex(where: { $0.id == anchor.id }) else { return nil }
            let position = side == "before" ? index - 1 : index + 1
            guard ordered.indices.contains(position) else { return nil }
            return (ordered[position], "The visit scheduled \(side) \(anchor.clientName)")
        }

        if p(#"\bafter (this|that|my current|the current|the active)\b|\bcomes after\b|\bnext planned\b"#, asked) {
            let ordered = round.ordered
            let remaining = AssistantQueries.remaining(round.visits)
            let following: [Visit]
            if let active = round.active, let index = ordered.firstIndex(where: { $0.id == active.id }) {
                following = remaining.filter { candidate in
                    (ordered.firstIndex { $0.id == candidate.id } ?? 0) > index
                }
            } else {
                following = remaining
            }
            guard let next = following.first else { return nil }
            return (next, "The visit after the one in hand")
        }

        if p(#"\b(active|current|ongoing|in progress)\b"#, asked), let active = round.active {
            return (active, "The visit in hand")
        }

        if p(#"\bnext\b"#, asked), let next = round.active ?? round.upNext {
            return (next, "The next visit")
        }

        // "Who is my last visit?" reads the timetable; "who did I last visit?"
        // asks what was watched finishing, and belongs to completion history.
        if p(#"\b(last|final)\b"#, asked),
           !p(#"\bremain|\bleft\b|\bstill\b"#, asked),
           !p(#"\bdid (i|we)\b|\bjust (finish|finished|completed)\b"#, asked),
           let last = round.ordered.last {
            return (last, "The last visit scheduled")
        }

        return nil
    }

    // MARK: - More of the same result

    /// "Are there any more?" — what the conditions match beyond what was named.
    func anyMore(_ asked: String) -> LocalAnswer? {
        guard p(#"\bis (it|that|this) just\b|\bany more\b|\bany others\b|\b(anyone|anybody) else\b"#, asked)
            || p(#"\bany other\s*[?.!]*$"#, asked) else { return nil }

        guard let context, let query = context.query else { return nil }

        let matched = AssistantSelectionEngine.execute(query, in: round).visits
        let rest = matched.filter { !context.visitIDs.contains($0.id) }

        guard !rest.isEmpty else {
            return LocalAnswer(
                text: "No more matching visits are recorded in that result set.",
                kind: .selection,
                selection: context
            )
        }

        return LocalAnswer(
            text: "\(AssistantPhrasing.plural(rest.count, "other visit")): \(AssistantPhrasing.names(rest)).",
            kind: .selection,
            selection: AssistantSelection(
                visitIDs: rest.map(\.id),
                lastKind: .selection,
                query: query
            )
        )
    }
}
