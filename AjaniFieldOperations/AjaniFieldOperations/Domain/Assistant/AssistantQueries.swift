import Foundation

/// A task and the visit it belongs to.
nonisolated struct TaskMatch: Hashable, Sendable {
    let visit: Visit
    let task: VisitTask
}

/// The result of searching the round's checklists.
nonisolated struct TaskSearchResult: Hashable, Sendable {
    let matches: [TaskMatch]
    let words: [String]
    /// True when every word found nothing and a single word was used instead.
    let loose: Bool

    var visits: [Visit] {
        var seen = Set<Visit.ID>()
        return matches.compactMap { match in
            seen.insert(match.visit.id).inserted ? match.visit : nil
        }
    }
}

/// Reusable questions about the round.
///
/// Every helper reads the current visits and returns data — never text and never
/// a modified round. The phrasing lives next door; this is what it phrases, so an
/// equivalent question asked three ways reaches the same selector.
///
/// Nothing is hardcoded to a particular person: every answer is derived from
/// whatever the round currently holds.
nonisolated enum AssistantQueries {
    // MARK: - Ordering

    static func allVisits(_ visits: [Visit]) -> [Visit] {
        ShiftPlanner.chronological(visits)
    }

    static func remaining(_ visits: [Visit]) -> [Visit] {
        allVisits(visits).filter { !$0.status.isResolved }
    }

    static func byStatus(_ visits: [Visit], _ status: VisitStatus) -> [Visit] {
        allVisits(visits).filter { $0.status == status }
    }

    static func priority(_ visits: [Visit]) -> [Visit] {
        allVisits(visits).filter { $0.priority == .priority }
    }

    static func withNotes(_ visits: [Visit]) -> [Visit] {
        allVisits(visits).filter { !$0.operationalNotes.isEmpty }
    }

    // MARK: - Tasks

    static func taskSummary(_ visit: Visit) -> (done: [VisitTask], remaining: [VisitTask], total: Int, allDone: Bool) {
        let done = visit.tasks.filter(\.isComplete)
        let remaining = visit.tasks.filter { !$0.isComplete }
        return (done, remaining, visit.tasks.count, !visit.tasks.isEmpty && remaining.isEmpty)
    }

    static func taskTotals(_ visits: [Visit]) -> (total: Int, done: Int, outstanding: Int, due: Int) {
        let all = visits.flatMap(\.tasks)
        let due = visits
            .filter { !$0.status.isResolved }
            .flatMap { $0.tasks.filter { !$0.isComplete } }

        return (
            all.count,
            all.filter(\.isComplete).count,
            all.filter { !$0.isComplete }.count,
            due.count
        )
    }

    // MARK: - Schedule

    static func durationMinutes(_ visit: Visit) -> Int {
        visit.scheduledDurationMinutes
    }

    static func durationExtremes(_ visits: [Visit]) -> (shortest: Visit?, longest: Visit?) {
        let sorted = allVisits(visits).sorted { durationMinutes($0) < durationMinutes($1) }
        return (sorted.first, sorted.last)
    }

    // MARK: - Comparisons

    enum Comparator: String, Hashable, Sendable, CaseIterable {
        case more, fewer, least, most, exactly

        /// The wording an answer uses to repeat the comparison back.
        var phrase: String {
            switch self {
            case .more: "more than"
            case .fewer: "fewer than"
            case .least: "at least"
            case .most: "at most"
            case .exactly: "exactly"
            }
        }

        fileprivate var pattern: String {
            switch self {
            case .more: #"\b(more than|greater than|over|above)\b"#
            case .fewer: #"\b(fewer than|less than|under|below)\b"#
            case .least: #"\bat least\b"#
            case .most: #"\b(at most|no more than)\b"#
            case .exactly: #"\b(exactly|precisely|just)\b"#
            }
        }

        func test(_ count: Int, _ n: Int) -> Bool {
            switch self {
            case .more: count > n
            case .fewer: count < n
            case .least: count >= n
            case .most: count <= n
            case .exactly: count == n
            }
        }
    }

    private static let numberWords: [String: Int] = [
        "zero": 0, "one": 1, "two": 2, "three": 3, "four": 4, "five": 5,
        "six": 6, "seven": 7, "eight": 8, "nine": 9, "ten": 10
    ]

    /// A comparison the question makes, or `nil`.
    ///
    /// The number has to be the one the comparator introduces: "more than 3
    /// tasks today" compares against three, and reading any digit in the
    /// sentence would just as happily compare against a clock time.
    static func readComparison(_ phrase: String) -> (comparator: Comparator, count: Int)? {
        let words = numberWords.keys.joined(separator: "|")

        for comparator in Comparator.allCases {
            let pattern = "\(comparator.pattern)\\s+(\\d{1,2}|\(words))\\b"
            guard let range = phrase.range(of: pattern, options: [.regularExpression, .caseInsensitive]) else {
                continue
            }

            let matched = String(phrase[range]).lowercased()
            if let digits = matched.range(of: #"\d{1,2}"#, options: .regularExpression),
               let value = Int(matched[digits]) {
                return (comparator, value)
            }
            for (word, value) in numberWords where matched.range(of: "\\b\(word)\\b", options: .regularExpression) != nil {
                return (comparator, value)
            }
        }

        return nil
    }

    /// Visits whose recorded task count satisfies a comparison.
    static func visits(_ visits: [Visit], taskCount comparator: Comparator, _ n: Int) -> [Visit] {
        allVisits(visits).filter { comparator.test($0.tasks.count, n) }
    }

    // MARK: - Similarity

    /// One visit's task set against another's.
    struct Similarity: Hashable, Sendable {
        let task: VisitTask
        let other: Visit
        let candidate: VisitTask
        let shared: [String]
    }

    /// Tasks elsewhere on the round that genuinely resemble this visit's.
    ///
    /// Resemblance means shared recorded wording — at least `minimumShared`
    /// significant words — and nothing else. One shared word is a coincidence:
    /// "Check wound dressing" and "Support with washing and dressing" share a
    /// word and are not the same job. The bar is set where it reports an
    /// operational overlap and declines to invent a clinical one.
    static func similarTasks(in visits: [Visit], to visit: Visit, minimumShared: Int = 2) -> [Similarity] {
        var found: [Similarity] = []

        for task in visit.tasks {
            let mine = Set(searchWords(taskText(task)))

            for other in allVisits(visits) where other.id != visit.id {
                for candidate in other.tasks {
                    let shared = Set(searchWords(taskText(candidate))).intersection(mine)
                    if shared.count >= minimumShared {
                        found.append(
                            Similarity(task: task, other: other, candidate: candidate, shared: shared.sorted())
                        )
                    }
                }
            }
        }

        return found
    }

    // MARK: - Contact instructions

    /// What a mention of contact actually instructs.
    enum ContactKind: Hashable, Sendable {
        case preVisit, outgoing, incoming, conditional
    }

    struct ContactMention: Hashable, Sendable {
        let visit: Visit
        let text: String
        let kind: ContactKind
    }

    /// Contact mentions across the round, grouped by what they instruct.
    ///
    /// Not every sentence containing "call" asks the practitioner to telephone
    /// anyone. "Daughter usually calls around nine" describes an incoming call,
    /// and "escalate any new pain to the duty line" is conditional on something
    /// happening. Each is recognised separately so a question about pre-visit
    /// calls is never handed a conditional escalation instead.
    static func contactMentions(in visits: [Visit]) -> [ContactMention] {
        let preVisit = #"\b(ring|call|phone|contact)\b[^.]*\b(before|prior to|ahead of|in advance)\b|\b(before|prior to|ahead of)\b[^.]*\b(ring|call|phone|contact)(ing)?\b"#
        let incoming = #"\b(daughter|son|family|relative|neighbour|office|they|who)\b[^.]*\b(calls?|rings?|phones?|will call|usually calls)\b"#
        let conditional = #"\b(escalate|if |should any|any new|duty line|out of hours)\b"#
        let outgoing = #"\b(ring|call|phone|contact)\b"#
        let negated = #"\b(do not|don\u{2019}t|don't|no need to)\b"#

        func matches(_ pattern: String, _ text: String) -> Bool {
            text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
        }

        var found: [ContactMention] = []

        for visit in allVisits(visits) {
            let sources = visit.operationalNotes + visit.tasks.map { taskText($0) }

            for text in sources {
                // Most specific first, so each mention lands in exactly one group.
                if matches(incoming, text) {
                    found.append(ContactMention(visit: visit, text: text, kind: .incoming))
                } else if matches(conditional, text) && matches(preVisit, text) {
                    found.append(ContactMention(visit: visit, text: text, kind: .conditional))
                } else if matches(preVisit, text) && !matches(negated, text) {
                    found.append(ContactMention(visit: visit, text: text, kind: .preVisit))
                } else if matches(conditional, text) && matches(outgoing, text) {
                    found.append(ContactMention(visit: visit, text: text, kind: .conditional))
                } else if matches(conditional, text) && matches(#"\bduty line\b"#, text) {
                    found.append(ContactMention(visit: visit, text: text, kind: .conditional))
                } else if matches(outgoing, text) {
                    found.append(ContactMention(visit: visit, text: text, kind: .outgoing))
                }
            }
        }

        return found
    }

    // MARK: - Text matching

    /// Words too common to narrow anything, plus the vocabulary of asking.
    private static let noise: Set<String> = [
        "the", "a", "an", "and", "or", "of", "to", "for", "in", "on", "at", "by",
        "with", "any", "all", "some", "my", "me", "i", "is", "are", "was", "were",
        "do", "does", "did", "has", "have", "had", "need", "needs", "needed",
        "require", "requires", "required", "who", "what", "which", "whose", "how",
        "many", "much", "today", "visit", "visits", "task", "tasks", "client",
        "clients", "patient", "patients", "person", "people", "anyone", "anybody",
        "someone", "somebody", "left", "remaining", "still", "been", "be", "get",
        "their", "his", "her", "this", "that", "these", "those", "include",
        "includes", "including", "about", "there", "it", "one", "ones",
        "complete", "completed", "completes", "done", "finish", "finished",
        "outstanding", "ticked", "regarding", "related", "similar", "other"
    ]

    /// A small operational vocabulary: words a practitioner might type for
    /// something the records word differently. Nothing here maps one clinical
    /// idea onto another — "med" and "medication" are the same word, "wound" and
    /// "dressing" are not.
    private static let synonyms: [String: [String]] = [
        "med": ["medication"],
        "meds": ["medication"],
        "medicine": ["medication"],
        "ring": ["call", "phone", "contact"],
        "phone": ["call", "ring", "contact"],
        "contact": ["call", "ring", "phone"],
        "call": ["ring", "phone", "contact"],
        "stroll": ["walk"],
        "bathe": ["wash"],
        "shower": ["wash"],
        "jab": ["injection"]
    ]

    /// Light stemming: enough to let ordinary inflection through, never below
    /// three characters so short words are left alone rather than shredded.
    private static func stem(_ word: String) -> String {
        for ending in ["ings", "ing", "ies", "ed", "es", "s"] {
            if word.count - ending.count >= 3 && word.hasSuffix(ending) {
                let base = String(word.dropLast(ending.count))
                return ending == "ies" ? base + "y" : base
            }
        }
        return word
    }

    private static func variants(_ word: String) -> Set<String> {
        let base = stem(word)
        var found: Set<String> = [word, base]

        for key in [word, base] {
            for synonym in synonyms[key] ?? [] {
                found.insert(synonym)
                found.insert(stem(synonym))
            }
        }

        return found.filter { $0.count >= 3 }
    }

    private static func tokens(_ text: String) -> [String] {
        text.lowercased()
            .replacingOccurrences(of: "\u{2019}", with: "")
            .replacingOccurrences(of: "'", with: "")
            .split { !$0.isLetter }
            .map(String.init)
    }

    /// A word matches text if any of its forms appears in it, so "walking" finds
    /// "Walk…", "dressings" finds "dressing" and "meds" finds "medication".
    private static func alike(_ word: String, _ text: String) -> Bool {
        let forms = variants(word)
        return tokens(text).contains { token in
            !variants(token).isDisjoint(with: forms)
        }
    }

    static func searchWords(_ phrase: String) -> [String] {
        tokens(phrase)
            .flatMap { $0.split(separator: "-").map(String.init) }
            .filter { $0.count >= 3 && !noise.contains($0) }
    }

    private static func taskText(_ task: VisitTask) -> String {
        "\(task.title) \(task.detail ?? "")"
    }

    /// Tasks across the round matching a phrase.
    ///
    /// Tries for every word first, so "wound dressing" means both. Falls back to
    /// any single word when that finds nothing, and says which it did.
    static func matchTasks(_ visits: [Visit], phrase: String) -> TaskSearchResult {
        let words = searchWords(phrase)
        guard !words.isEmpty else { return TaskSearchResult(matches: [], words: [], loose: false) }

        func collect(_ predicate: (String) -> Bool) -> [TaskMatch] {
            allVisits(visits).flatMap { visit in
                visit.tasks
                    .filter { predicate(taskText($0)) }
                    .map { TaskMatch(visit: visit, task: $0) }
            }
        }

        let strict = collect { text in words.allSatisfy { alike($0, text) } }
        if !strict.isEmpty { return TaskSearchResult(matches: strict, words: words, loose: false) }

        let loose = collect { text in words.contains { $0.count >= 4 && alike($0, text) } }
        return TaskSearchResult(matches: loose, words: words, loose: !loose.isEmpty)
    }

    /// A named task on one visit, matched loosely.
    static func findTask(in visit: Visit, phrase: String) -> VisitTask? {
        let words = searchWords(phrase)
        guard !words.isEmpty else { return nil }

        return visit.tasks.first { task in words.allSatisfy { alike($0, taskText(task)) } }
            ?? visit.tasks.first { task in words.contains { $0.count >= 4 && alike($0, taskText(task)) } }
    }

    /// Visits whose service type matches a phrase.
    static func matchServices(_ visits: [Visit], phrase: String) -> [Visit] {
        let words = searchWords(phrase)
        guard !words.isEmpty else { return [] }
        return allVisits(visits).filter { visit in
            words.allSatisfy { alike($0, visit.visitType) }
        }
    }

    /// Visits whose operational notes match a phrase.
    static func matchNotes(_ visits: [Visit], phrase: String) -> [Visit] {
        let words = searchWords(phrase)
        guard !words.isEmpty else { return [] }
        return allVisits(visits).filter { visit in
            let text = visit.operationalNotes.joined(separator: " ")
            return words.allSatisfy { alike($0, text) }
        }
    }
}
