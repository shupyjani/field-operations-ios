import Foundation

/// A schedule boundary, read from recorded start times.
///
/// No elapsed clock and no route assumptions: "before" and "after" are strict,
/// "between" is inclusive, and every comparison is against the time the visit
/// is scheduled to start.
nonisolated struct ScheduleBoundary: Hashable, Sendable {
    var from: Int?
    var to: Int?
    var inclusive: Bool

    func admits(_ minutes: Int) -> Bool {
        if let from, inclusive ? minutes < from : minutes <= from { return false }
        if let to, inclusive ? minutes > to : minutes >= to { return false }
        return true
    }
}

/// An explicit selection of records, kept as the conditions that produced it
/// rather than as the records themselves.
///
/// Persisting the query and never its totals is what lets a later turn refine
/// the same question against the round as it now stands, instead of replaying
/// a stale list.
nonisolated struct SelectionQuery: Hashable, Sendable {
    enum Subject: String, Hashable, Sendable {
        case visits, tasks
    }

    enum Operation: String, Hashable, Sendable {
        case list, count, sumDuration
    }

    struct Comparison: Hashable, Sendable {
        let comparator: AssistantQueries.Comparator
        let count: Int
    }

    var subject: Subject = .visits
    var operation: Operation = .list
    var comparison: Comparison?
    var priority: Bool?
    var personIDs: [Visit.ID]?
    var statuses: [VisitStatus] = []
    var excludedStatuses: [VisitStatus] = []
    /// Restricted to visits that are neither completed nor cancelled.
    var actionable = false
    /// `true` for checked tasks, `false` for outstanding ones, `nil` for either.
    var done: Bool?
    var conceptIDs: [String] = []
    var conjunction: AssistantReading.Conjunction = .and
    var time: ScheduleBoundary?
    var photograph: Bool?
}

nonisolated enum AssistantSelectionEngine {
    private static func matches(_ pattern: String, _ text: String) -> Bool {
        text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }

    private static func firstMatch(_ pattern: String, _ text: String) -> String? {
        guard let range = text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) else {
            return nil
        }
        return String(text[range])
    }

    /// A visit that is closed: its record stands, but no work remains on it.
    static func isClosed(_ visit: Visit) -> Bool {
        visit.status == .completed || visit.status == .cancelled
    }

    // MARK: - Schedule boundaries

    private static let timeToken =
        #"(?:noon|midday|(?:[01]?\d|2[0-3]):[0-5]\d(?:\s*(?:am|pm))?|(?:1[0-2]|[1-9])\s*(?:am|pm))"#

    /// Minutes past midnight for a spoken or written time.
    static func minutes(of token: String) -> Int? {
        if matches(#"noon|midday"#, token) { return 720 }

        guard let firstNumber = firstMatch(#"\d+"#, token), let hour = Int(firstNumber) else {
            return nil
        }
        let minute = firstMatch(#":(\d{2})"#, token)
            .flatMap { Int($0.dropFirst()) } ?? 0

        guard matches(#"am|pm"#, token) else { return hour * 60 + minute }
        return (hour % 12) * 60 + minute + (matches(#"pm"#, token) ? 720 : 0)
    }

    static func scheduleBoundary(_ text: String) -> ScheduleBoundary? {
        if let between = firstMatch("between (\(timeToken)) and (\(timeToken))", text) {
            let parts = between.components(separatedBy: " and ")
            guard parts.count == 2,
                  let from = minutes(of: parts[0].replacingOccurrences(of: "between ", with: "")),
                  let to = minutes(of: parts[1]) else { return nil }
            return ScheduleBoundary(from: from, to: to, inclusive: true)
        }

        guard let edge = firstMatch("\\b(before|after) (\(timeToken))\\b", text),
              let value = minutes(of: edge) else { return nil }

        return matches(#"^before\b"#, edge)
            ? ScheduleBoundary(to: value, inclusive: false)
            : ScheduleBoundary(from: value, inclusive: false)
    }

    /// Minutes past midnight at which a visit is scheduled to start, read in
    /// the same calendar the interface prints times in.
    static func startMinutes(_ visit: Visit) -> Int {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: visit.scheduledStart)
        return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }

    // MARK: - Concepts

    /// The concepts a question names, with a broad one dropped when a precise
    /// one that refines it is present — "wound dressing" outranks "dressing".
    static func concepts(in text: String) -> [String] {
        let found = AssistantConcepts.all.filter { matches($0.asks, text) }
        return found.filter { concept in
            !found.contains { other in
                other.precise && other.id != concept.id
                    && (other.id.hasPrefix("\(concept.id)-") || other.related == concept.id)
            }
        }
        .map(\.id)
    }

    // MARK: - Reading

    static func readSelection(_ text: String, person: Visit?) -> SelectionQuery {
        let reading = AssistantInterpreter.interpret(text)

        let exclusion = firstMatch(
            #"\b(excluding|except|other than|not)\b[^?]*\b(completed|cancelled|planned|arrived)\b"#,
            text
        )
        let excludedStatuses = exclusion.map { AssistantInterpreter.readStatuses($0) } ?? []

        // "How many completed tasks?" names a checked state, not a visit status.
        let named = reading.statuses.filter {
            !($0 == .completed && matches(#"completed tasks"#, text))
        }

        let actionable = AssistantInterpreter.isWorkRemaining(text) || matches(#"\bunresolved\b"#, text)

        let subject: SelectionQuery.Subject
        if matches(#"\b(?:which|who|list|show)\b.*\b(?:visits|people|clients)\b|^who\b"#, text) {
            subject = .visits
        } else if reading.subject == .task || matches(#"outstanding work"#, text) {
            subject = .tasks
        } else {
            subject = .visits
        }

        let operation: SelectionQuery.Operation
        if matches(#"\b(?:scheduled|visit) (?:time|duration)\b"#, text),
           matches(#"how much|total|sum"#, text) {
            operation = .sumDuration
        } else {
            operation = reading.operation == .count ? .count : .list
        }

        let done: Bool?
        if actionable && subject == .visits && !matches(#"\b(tasks?|checked|unchecked)\b"#, text) {
            done = nil
        } else if actionable {
            done = false
        } else {
            done = reading.done
        }

        let photograph: Bool? = matches(#"photograph|photo\b"#, text)
            ? !matches(#"don'?t|doesn'?t|do(?:es)? not|not required|no need|without"#, text)
            : nil

        return SelectionQuery(
            subject: subject,
            operation: operation,
            comparison: AssistantQueries.readComparison(text).map {
                SelectionQuery.Comparison(comparator: $0.comparator, count: $0.count)
            },
            priority: reading.priority,
            personIDs: person.map { [$0.id] },
            statuses: named.filter { !excludedStatuses.contains($0) },
            excludedStatuses: excludedStatuses,
            actionable: actionable,
            done: done,
            conceptIDs: concepts(in: text),
            conjunction: reading.conjunction,
            time: scheduleBoundary(text),
            photograph: photograph
        )
    }

    // MARK: - Execution

    static func execute(_ query: SelectionQuery, in round: AssistantRound) -> (visits: [Visit], tasks: [TaskMatch]) {
        var visits = AssistantQueries.allVisits(round.visits).filter { visit in
            (query.personIDs.map { $0.contains(visit.id) } ?? true)
                && (query.statuses.isEmpty || query.statuses.contains(visit.status))
                && !query.excludedStatuses.contains(visit.status)
                && (!query.actionable || !isClosed(visit))
                && (query.priority != true || visit.priority == .priority)
        }

        if let time = query.time {
            visits = visits.filter { time.admits(startMinutes($0)) }
        }

        let concepts = query.conceptIDs.compactMap { AssistantConcepts.concept(id: $0) }

        func admits(_ task: VisitTask) -> Bool {
            if let done = query.done, query.operation != .sumDuration, task.isComplete != done {
                return false
            }
            if let wanted = query.photograph {
                guard AssistantTaskProperties.photographRequirement(task) == wanted else { return false }
            }
            return true
        }

        // "Who has both?" — every concept must be met, though not by one task.
        if !concepts.isEmpty && query.conjunction == .and {
            visits = visits.filter { visit in
                concepts.allSatisfy { concept in
                    visit.tasks.contains { admits($0) && matches(concept.label, $0.title) }
                }
            }
        }

        var tasks = visits.flatMap { visit in
            visit.tasks
                .filter { task in
                    admits(task)
                        && (concepts.isEmpty || concepts.contains { matches($0.label, task.title) })
                }
                .map { TaskMatch(visit: visit, task: $0) }
        }

        let hasTaskCondition = !concepts.isEmpty || query.done != nil || query.photograph != nil
        if query.subject == .visits && hasTaskCondition && query.operation != .sumDuration {
            visits = visits.filter { visit in tasks.contains { $0.visit.id == visit.id } }
        }

        if let comparison = query.comparison {
            visits = visits.filter { visit in
                let count = tasks.filter { $0.visit.id == visit.id }.count
                return comparison.comparator.test(count, comparison.count)
            }
        }

        tasks = tasks.filter { match in visits.contains { $0.id == match.visit.id } }
        return (visits, tasks)
    }

    // MARK: - Phrasing

    /// A time-bounded selection is narrower than its status filter, so naming
    /// only the status would overstate what was counted.
    private static func scope(_ query: SelectionQuery) -> String {
        if query.actionable { return " on unresolved visits" }
        if query.time != nil { return " across the selected visits" }
        if !query.statuses.isEmpty {
            return " on \(query.statuses.map(\.snapshotValue).joined(separator: " or ")) visits"
        }
        return " in this selection"
    }

    static func format(_ query: SelectionQuery, in round: AssistantRound) -> LocalAnswer {
        let (visits, tasks) = execute(query, in: round)
        let scope = scope(query)
        let boundary = query.time != nil
            ? " Schedule boundaries use visit start times; before/after are exclusive and between is inclusive."
            : ""

        let text: String
        if let comparison = query.comparison {
            let named = visits.isEmpty ? "No visits" : visits.map(\.clientName).joined(separator: ", ")
            text = "\(named) have \(comparison.comparator.phrase) \(comparison.count) recorded tasks\(scope).\(boundary)"
        } else if query.operation == .sumDuration {
            let total = visits.reduce(0) { $0 + AssistantQueries.durationMinutes($1) }
            text = "\(total) scheduled minutes across \(visits.count) visits. This sums full recorded visit slots, excluding travel, gaps and elapsed time."
        } else if query.operation == .count {
            let count = query.subject == .tasks ? tasks.count : visits.count
            text = "\(count) \(query.subject.rawValue)\(scope).\(boundary)"
        } else if query.subject == .visits {
            text = visits.isEmpty
                ? "No visits match these conditions.\(boundary)"
                : "\(visits.count) matching \(visits.count == 1 ? "visit" : "visits"): \(visits.map { "\($0.clientName) (\($0.status.title))" }.joined(separator: "; ")).\(boundary)"
        } else {
            text = tasks.isEmpty
                ? "No matching \(query.done == false ? "unchecked " : "")tasks are recorded\(scope)."
                : tasks.map { "\($0.visit.clientName) \u{2014} \($0.task.title) (\($0.task.isComplete ? "checked" : "unchecked"))" }
                    .joined(separator: "; ") + "."
        }

        return LocalAnswer(
            text: text,
            kind: .selection,
            selection: AssistantSelection(
                visitIDs: visits.map(\.id),
                taskIDs: tasks.map(\.task.id),
                lastKind: .selection,
                query: query
            )
        )
    }
}
