import Foundation

/// Reading a question before answering it.
///
/// One job: turn a sentence into a small structured description of what was
/// asked. It selects no records and writes no text — those are the next two
/// stages, and keeping them apart is what stops a phrasing fix in one quietly
/// changing the other.
///
/// Deliberately not a general parser. The round is a fixed, small domain, and
/// the vocabulary that reaches it is the vocabulary of that domain.
nonisolated struct AssistantReading: Hashable, Sendable {
    enum Subject: String, Hashable, Sendable {
        case conversation, control, duration, progress, cancellation, contact
        case task, note, address, reference, priority, service, schedule, status, visit
    }

    enum Operation: String, Hashable, Sendable {
        case explain, comparison, count, completion, existence, list, identify
    }

    enum Conjunction: String, Hashable, Sendable {
        case and, or
    }

    let subject: Subject?
    let operation: Operation?
    /// Visit statuses the question names.
    let statuses: [VisitStatus]
    /// `true` for checked tasks, `false` for outstanding ones, `nil` when the
    /// question does not say.
    let done: Bool?
    let priority: Bool?
    let conjunction: Conjunction
}

nonisolated enum AssistantInterpreter {
    /// Meaning-preserving only: phones produce curly quotes by default and
    /// every pattern here is written with the plain ones.
    static func normalise(_ question: String) -> String {
        question
            .replacingOccurrences(of: "[\u{2018}\u{2019}\u{02BC}]", with: "'", options: .regularExpression)
            .replacingOccurrences(of: "[\u{201C}\u{201D}]", with: "\"", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func matches(_ pattern: String, _ text: String) -> Bool {
        text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }

    /// Wording that asks what is still to be done, rather than what is recorded.
    static func isWorkRemaining(_ text: String) -> Bool {
        matches(
            #"\b(still (?:need doing|to do|due)|left to do|not done yet|outstanding work|work (?:left|remaining)|tasks? (?:are )?left|remaining tasks?)\b"#,
            text
        )
    }

    // MARK: - Subject

    /// First match wins, so the order is the priority: "how long is that visit?"
    /// is a duration question rather than a visit question.
    private static let subjects: [(AssistantReading.Subject, String)] = [
        (.conversation, #"\b(question|questions|message|messages)\b"#),
        (.control, #"\bhow (do|can) (i|you)\b|\bwhat happens (if|when)\b|\bhow does .* work\b|\bwhy (can'?t|is|are|does)\b|\bwhere (do|can) i (find|tap|press)\b"#),
        (.duration, #"\bhow long\b|\bduration\b|\bhow many minutes\b|\b(longest|shortest)\b"#),
        (.progress, #"\bprogress\b|\bhow far\b|\bso far\b"#),
        (.cancellation, #"\bcancel"#),
        (.contact, #"\b(ring|rings|ringing|call|calls|calling|phone|phoning|telephone|contact(ed|ing|s)?)\b"#),
        (.task, #"\btask|\bchecklist\b|\btick|\bto ?do\b"#),
        (.note, #"\bnote|\bwarning|\baccess\b"#),
        (.address, #"\b(address|postcode|district|where (is|does|do)|live|lives)\b"#),
        (.reference, #"\brefer(ence)?\b"#),
        (.priority, #"\bpriorit"#),
        (.service, #"\b(service|type of visit|what kind of visit)\b"#),
        (.schedule, #"\b(schedule|shift|rota|when\b|what time|order)\b"#),
        (.status, #"\b(status|planned|completed|cancelled|arrived|en ?route|travelling|active|ongoing|in progress|finished|done|outstanding|remaining)\b"#),
        (.visit, #"\b(visits?|clients?|patients?|people|round|appointments?)\b"#)
    ]

    static func readSubject(_ text: String) -> AssistantReading.Subject? {
        if matches(#"\b(tasks?|checklist)\b"#, text),
           !matches(#"\bhow (do|can)|\bwhy|\bwhat happens"#, text) {
            return .task
        }
        for (subject, pattern) in subjects where matches(pattern, text) {
            return subject
        }
        return nil
    }

    // MARK: - Operation

    private static let operations: [(AssistantReading.Operation, String)] = [
        (.explain, #"\bhow (do|can) (i|you)\b|\bwhat happens (if|when)\b|\bhow does\b|\bwhy (can'?t|is|are|does|do)\b|\bexplain\b"#),
        (.comparison, #"\b(more|fewer|less) than\b|\bat (least|most)\b|\bexactly\b|\b(longest|shortest)\b"#),
        (.count, #"\bhow many\b|\bhow much\b|\bnumber of\b|\bcount\b|\btotal\b"#),
        (.completion, #"\b(has|have|is|are|was|were)\b[^?]*\b(been )?(completed?|done|finished|ticked)\b"#),
        (.existence, #"\b(is|are) there\b|\b(does|do) (anyone|anybody|any)\b|\bany\b.*\?|\bdo i (have|need)\b"#),
        (.list, #"\b(list|show|what are|which are|tell me)\b|\bwhat (tasks|visits|notes)\b"#),
        (.identify, #"\bwho\b|\bwhich\b|\bwhat\b|\bwhen\b|\bwhere\b"#)
    ]

    static func readOperation(_ text: String) -> AssistantReading.Operation? {
        for (operation, pattern) in operations where matches(pattern, text) {
            return operation
        }
        return nil
    }

    // MARK: - Filters

    private static let statusWords: [(VisitStatus, String)] = [
        (.planned, #"\bplanned\b"#),
        (.completed, #"\bcompleted?\b|\bfinished\b"#),
        (.cancelled, #"\bcancelled\b"#),
        (.arrived, #"\barrived\b"#),
        (.enRoute, #"\ben ?route\b|\btravelling\b"#)
    ]

    static func readStatuses(_ text: String) -> [VisitStatus] {
        statusWords.filter { matches($0.1, text) }.map(\.0)
    }

    static func readDone(_ text: String) -> Bool? {
        if isWorkRemaining(text)
            || matches(#"\b(outstanding|unchecked|unticked|remaining|still (to do|due|left)|not (yet )?(done|completed|ticked)|left to do)\b"#, text) {
            return false
        }
        if matches(#"\b(checked|ticked|already done|completed tasks?|done tasks?)\b"#, text) {
            return true
        }
        return nil
    }

    static func interpret(_ question: String) -> AssistantReading {
        let text = normalise(question)
        return AssistantReading(
            subject: readSubject(text),
            operation: readOperation(text),
            statuses: readStatuses(text),
            done: readDone(text),
            priority: matches(#"\bpriorit"#, text) ? true : nil,
            conjunction: matches(#"\bor\b"#, text) ? .or : .and
        )
    }
}
