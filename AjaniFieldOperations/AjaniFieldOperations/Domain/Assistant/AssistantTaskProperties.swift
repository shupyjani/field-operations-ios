import Foundation

/// A recorded property a question can ask a task for.
///
/// Every one of these is a read-back of what the round happens to have written
/// down. Nothing here infers a value, and nothing here is advice: a medication
/// name is reported only because a task hint literally contains one, in the
/// same way a dressing type or an equipment model would be.
nonisolated enum TaskProperty: String, Hashable, Sendable, CaseIterable {
    case duration
    case repetitions
    case dressingType = "dressing type"
    case medicationName = "medication name"
    case dose
    case equipmentModel = "equipment model"
    case contactNumber = "contact number"
    case instructions
    case hint
    case completion

    /// Whether this is a recorded detail rather than the task's checked state.
    var isDetail: Bool { self != .completion }

    /// "a duration", "an equipment model" — the article the refusal needs.
    var withArticle: String {
        switch self {
        case .instructions, .repetitions: rawValue
        case .equipmentModel: "an \(rawValue)"
        default: "a \(rawValue)"
        }
    }
}

nonisolated enum AssistantTaskProperties {
    private static func matches(_ pattern: String, _ text: String) -> Bool {
        text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }

    /// Which property a question asks for, most specific first.
    ///
    /// Order is the design: "how long" is a duration before it is anything
    /// else, and a bare "done" is the checked state rather than a detail.
    static func read(_ text: String) -> TaskProperty? {
        if matches(#"\bhow long\b|\bduration\b"#, text) { return .duration }
        if matches(#"\bhow many times\b|\brepetitions?\b"#, text) { return .repetitions }
        if matches(#"\bdressing\b.*\b(type|product)\b|\b(type|product)\b.*\bdressing\b"#, text) {
            return .dressingType
        }
        if matches(#"\b(medication|medicine) name\b"#, text) { return .medicationName }
        if matches(#"\bdose|\bdosage\b"#, text) { return .dose }
        if matches(#"\bmodel\b"#, text) { return .equipmentModel }
        if matches(#"\b(contact|phone|telephone) number\b"#, text) { return .contactNumber }
        if matches(#"\binstructions?\b"#, text) { return .instructions }
        // "Which of her tasks need a photograph?" selects across a checklist;
        // "does that task need one?" reads one field.
        if matches(#"\bhint\b"#, text)
            || (matches(#"\bphotograph\b|\bphoto\b"#, text) && !matches(#"\bwhich\b|\btasks\b"#, text)) {
            return .hint
        }
        if matches(#"\b(done|completed|finished|checked|unchecked|outstanding|ticked)\b"#, text) {
            return .completion
        }
        return nil
    }

    /// Whether the question asks for what is *not* yet ticked.
    static func asksUnchecked(_ text: String) -> Bool {
        matches(#"\b(outstanding|unchecked|not (?:yet )?done)\b"#, text)
    }

    private static let numberWords: [String: Int] = [
        "once": 1, "twice": 2, "one": 1, "two": 2, "three": 3,
        "four": 4, "five": 5, "ten": 10
    ]

    private static func number(_ value: String) -> Int? {
        numberWords[value.lowercased()] ?? Int(value)
    }

    /// The keys a recorded detail uses to introduce each property.
    private static let keys: [TaskProperty: String] = [
        .dressingType: #"dressing (?:type|product)"#,
        .medicationName: #"(?:medication|medicine) name"#,
        .dose: #"(?:dose|dosage)"#,
        .equipmentModel: #"(?:equipment )?model"#,
        .contactNumber: #"(?:contact|phone|telephone) number"#,
        .instructions: #"instructions"#
    ]

    /// The value a record holds for one property, or `nil` when it holds none.
    ///
    /// Read off the task's own wording and its recorded detail, and nothing
    /// else. That is what keeps a missing duration missing: nothing here can
    /// reach the visit it belongs to, so an unrecorded task duration can never
    /// come back as the length of the visit.
    static func value(of property: TaskProperty, in source: String) -> String? {
        switch property {
        case .duration:
            guard let range = source.range(
                of: #"\b(\d+|one|two|three|four|five|ten)\s*(minutes?|mins?|hours?)\b"#,
                options: [.regularExpression, .caseInsensitive]
            ) else { return nil }
            let found = String(source[range])
            guard let digits = found.range(
                of: #"\d+|one|two|three|four|five|ten"#,
                options: [.regularExpression, .caseInsensitive]
            ), let count = number(String(found[digits])) else { return nil }
            return "\(count) \(matches(#"hour"#, found) ? "hours" : "minutes")"

        case .repetitions:
            if let range = source.range(of: #"\b(once|twice)\b"#, options: [.regularExpression, .caseInsensitive]),
               let count = number(String(source[range])) {
                return "\(count) \(count == 1 ? "time" : "times")"
            }
            guard let range = source.range(
                of: #"\b(\d+|one|two|three|four|five|ten)\s+times\b"#,
                options: [.regularExpression, .caseInsensitive]
            ) else { return nil }
            let found = String(source[range])
            guard let digits = found.range(
                of: #"\d+|one|two|three|four|five|ten"#,
                options: [.regularExpression, .caseInsensitive]
            ), let count = number(String(found[digits])) else { return nil }
            return "\(count) \(count == 1 ? "time" : "times")"

        case .completion, .hint:
            // Read straight off the task rather than parsed out of its wording.
            return nil

        default:
            guard let key = keys[property],
                  let range = source.range(
                      of: "\\b\(key)\\s*:\\s*([^.;\\n]+)",
                      options: [.regularExpression, .caseInsensitive]
                  ) else { return nil }
            let found = String(source[range])
            guard let colon = found.firstIndex(of: ":") else { return nil }
            let value = found[found.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            return value.isEmpty ? nil : value
        }
    }

    /// The text a property is read from: the task's own wording and its hint.
    static func source(_ task: VisitTask) -> String {
        "\(task.title). \(task.detail ?? "")"
    }

    /// Whether a recorded hint explicitly says a photograph is or is not needed.
    ///
    /// Explicit only. A task with no hint has not said "no photograph"; it has
    /// said nothing, and the difference is the whole point.
    static func photographRequirement(_ task: VisitTask) -> Bool? {
        let hint = task.detail ?? ""
        if matches(#"photograph(?:y)? (?:is )?not required|no photograph|do not (?:take|need).*photo"#, hint) {
            return false
        }
        if matches(#"photograph(?:y)? (?:is )?required|take (?:a )?photograph"#, hint) {
            return true
        }
        return nil
    }
}
