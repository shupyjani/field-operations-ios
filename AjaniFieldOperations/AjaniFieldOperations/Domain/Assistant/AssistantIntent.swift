import Foundation

/// What kind of question the reader is asking.
nonisolated enum AssistantIntent: String, Hashable, Sendable {
    /// An attempt to reach the machinery rather than the round.
    case disclosure
    /// A request for a clinical decision.
    case advice
    /// Sensitive ground with no lookup framing.
    case clinical
    /// A field the round does not record.
    case demographic
    /// A request for the assistant to change something.
    case mutation
    /// A request for recorded data.
    case lookup
    /// Anything else.
    case open

    /// Whether a question of this kind is asking for a clinical decision.
    var isClinical: Bool {
        self == .advice || self == .clinical
    }

    /// Whether the answer is decided locally and must never reach a provider.
    var isBoundary: Bool {
        self == .clinical || self == .advice || self == .disclosure || self == .mutation
    }
}

/// Telling a lookup from a request for clinical advice.
///
/// The distinction that matters is not the vocabulary but the speech act: is the
/// reader asking what is *recorded*, or what they should *do* about someone's
/// care? "Does anyone need wound dressing?" is a question about a checklist and
/// must be answered; "which dressing should I use?" is a clinical decision and
/// must not.
nonisolated enum AssistantClassifier {
    /// Asking what to do about someone's care. These outrank every lookup
    /// pattern: an interrogative does not decide the speech act, the verb does.
    private static let advice = [
        #"\b(which|what|whose)\b[^?]*\b(should (i|we)|(i|we) should)\b[^?]*\b(use|apply|give|do|choose|select|pick|put|administer|change|dress|treat|clean|prescribe)\b"#,
        #"\bwhat should (i|we)\b"#,
        #"\b(which|what)\b[^?]*\b(dressing|medication|medicine|drug|treatment|therapy|antibiotic|cream|ointment)\b[^?]*\bshould\b"#,
        #"\bwould you recommend\b"#,
        #"\bwhat do you (recommend|suggest|advise)\b"#,
        #"\bhow (should|do|would|can) (i|we|you)\b[^?]*\b(dress|treat|manage|administer|give|apply|handle|care for|clean|change)\b"#,
        #"\bshould (i|we)\b[^?]*\b(change|give|administer|apply|stop|start|increase|decrease|adjust|dress|treat|clean|withhold)\b"#,
        #"\b(diagnos|prognos)"#,
        #"\bsymptom"#,
        #"\bis it (safe|ok|okay|alright|advisable) to\b"#,
        #"\b(prescrib|contraindicat)"#,
        #"\b(999|emergency|ambulance|triage|resuscitat|sepsis|deteriorat)"#,
        #"\bclinical (advice|decision|judgement|judgment|opinion)"#,
        #"\b(recommend|advise|suggest)\b[^?]*\b(treatment|medication|dose|care)\b"#,
        #"\bwhat (treatment|care) does\b"#
    ]

    /// Asking what is written down.
    private static let lookup = [
        #"\b(does|do) (anyone|anybody|any visit|any client|any patient|any one)\b"#,
        #"\bwho (has|have|needs|need|is|are)\b"#,
        #"\bwhich (visit|visits|client|clients|patient|patients|one|ones|of)\b"#,
        #"\bhow many\b"#,
        #"\bhas\b[^?]*\bbeen (completed|done|ticked|finished)\b"#,
        #"\b(what|list|show|tell me)\b[^?]*\btasks?\b"#,
        #"\b(is|are)\b[^?]*\b(complete|completed|done|finished|outstanding|remaining)\b"#,
        #"\bany (task|tasks|note|notes|visit|visits)\b"#,
        #"\b(operational )?notes?\b"#
    ]

    /// Sensitive ground that no lookup framing rescues.
    private static let residualClinical = [
        #"\b(blood pressure|pain relief|painkiller|observations|obs)\b"#,
        #"\b(infection|wound care|pressure sore|catheter)\b"#,
        #"\bunwell|collapsed|bleeding|breathless\b"#
    ]

    /// Attempts to get at the machinery rather than the round.
    ///
    /// The key pattern has no leading word boundary: an underscore is a word
    /// character, so a screaming-snake-case variable name has none before "API".
    private static let disclosure = [
        #"\b(system|developer)\s+(prompt|instruction|message)"#,
        #"api[_\s-]?key|\b(secret|credential|token|password)|env(ironment)?[_\s-]?variable"#,
        #"\bignore (all |your |previous )*(instruction|rule|prompt)"#,
        #"\b(reveal|show|print|repeat|leak)\b[^?]*\b(prompt|instruction|configuration|config|key)"#
    ]

    /// Fields the round simply does not record.
    private static let demographic = [
        #"\b(men|man|women|woman|male|females?|gender|sex)\b"#,
        #"\b(age|ages|aged|how old|years old|date of birth|dob)\b"#,
        #"\b(ethnicity|ethnic|nationality|religion|language spoken)\b"#
    ]

    /// Asking the assistant to do something to the round.
    private static let mutation = [
        #"\b(restore|reopen|undo|complete|cancel|start|finish|tick|untick|update|change|edit|mark|set|book|move|reschedule)\b[^?]*\b(it|this|that|visit|task|for me|please)\b"#,
        #"\b(please|can you|could you|would you|go ahead and)\b[^?]*\b(complete|cancel|start|tick|update|change|mark)\b"#,
        // An imperative bolted on to a question with a conjunction is still an
        // imperative, and the sentence it is bolted on to does not soften it.
        #"\b(and|then|also)\s+(please\s+)?(restore|reopen|undo|complete|cancel|start|finish|tick|untick|update|change|edit|mark|set|book|move|reschedule)\b"#
    ]

    /// What kind of question this is.
    ///
    /// Order is the whole design. Security first, then anything asking for a
    /// clinical decision — no lookup phrasing can buy past that. Mutation next,
    /// so "cancel this for me" is answered as a request to act rather than
    /// searched for. Demographic sits above lookup because those questions are
    /// almost always phrased as one.
    static func classify(_ question: String) -> AssistantIntent {
        let asked = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !asked.isEmpty else { return .open }

        if matches(disclosure, asked) { return .disclosure }

        let recordedProperty = matches([#"\b(recorded|record|specif(?:y|ies|ied)|listed)\b"#], asked)
            && matches([#"\b(dose|dosage|medication name|medicine name)\b"#], asked)
        if matches(advice, asked)
            || (!recordedProperty && matches([#"\b(dose|dosage)\b|\bwhat (medication|medicine|drug|treatment|therapy)\b"#], asked)) {
            return .advice
        }

        // A question about what happened is a lookup even when it names an
        // action, so "did I complete Priya's visit?" is answered rather than
        // refused. An imperative bolted on to it is not.
        let cancellationRecord = matches([#"^(?:why (?:was|is|has)\b.*\bcancelled|what\b.*\b(?:cancellation reason|reason.*cancelled))\b"#], asked)
        let statusQuestion = cancellationRecord
            || matches([#"^(?:did i complete|have i completed|has .* been completed|are all .* tasks? done)\b"#], asked)
        if statusQuestion && !matches([#"\b(?:and|then|also)\s+(?:please\s+)?(?:complete|cancel|restore|tick|change|mark)\b|\bfor me\b"#], asked) {
            return .lookup
        }

        if matches(mutation, asked) { return .mutation }
        if matches(demographic, asked) { return .demographic }
        if matches(lookup, asked) { return .lookup }
        if matches(residualClinical, asked) { return .clinical }

        return .open
    }

    private static func matches(_ patterns: [String], _ text: String) -> Bool {
        patterns.contains { pattern in
            text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
        }
    }
}
