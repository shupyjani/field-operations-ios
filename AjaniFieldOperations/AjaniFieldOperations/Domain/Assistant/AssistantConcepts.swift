import Foundation

/// An operational idea a question might be about, and the wording the round
/// uses for it.
///
/// Two patterns each, kept deliberately apart: `asks` is tested against the
/// question, `label` against the recorded task. A question about administering
/// medication is a real question whose honest answer here is "nothing records
/// that" — and the only way to say so is to look for administration
/// specifically rather than for the word "medication".
nonisolated struct TaskConcept: Hashable, Sendable {
    let id: String
    /// Whether this concept exists to tell look-alike actions apart, and so must
    /// be consulted before any literal word search.
    let precise: Bool
    let asks: String
    let label: String
    /// How the concept is named in an answer.
    let noun: String
    /// The concept to offer instead when this one records nothing.
    let related: String?

    init(id: String, precise: Bool = false, asks: String, label: String, noun: String, related: String? = nil) {
        self.id = id
        self.precise = precise
        self.asks = asks
        self.label = label
        self.noun = noun
        self.related = related
    }
}

nonisolated enum AssistantConcepts {
    /// Ordered most specific first. "Administer medication" must be read before
    /// "medication", and "wound dressing" before "dressing".
    static let all: [TaskConcept] = [
        TaskConcept(
            id: "hygiene",
            asks: #"\b(?:personal\s+)?hygiene\b"#,
            label: #"\b(wash|washing|bath|bathing|shower|oral hygiene|brush(?:ing)? (?:the |their )?teeth)\b"#,
            noun: "personal hygiene"
        ),
        TaskConcept(
            id: "mobility",
            asks: #"\bmobility\b"#,
            label: #"\b(walk|walking|hallway|seated exercises|mobility exercises)\b"#,
            noun: "mobility"
        ),
        TaskConcept(
            id: "medication-administer",
            precise: true,
            asks: #"\b(administer|administering|administration|give|giving|dispense|dispensing|hand out)\b[^?]*\b(med|meds|medication|medicines?|drugs?|tablets?|dose|doses)\b"#,
            label: #"\b(administer|administering|dispense|dispensing|inject|injection)\b"#,
            noun: "administering medication",
            related: "medication-prompt"
        ),
        TaskConcept(
            id: "medication-prompt",
            precise: true,
            asks: #"\bprompt(ing|s)?\b[^?]*\b(med|meds|medication|medicines?)\b|\bmedication prompt"#,
            label: #"\bprompt\b[^.]*\b(medication|medicine|meds)\b"#,
            noun: "prompting medication"
        ),
        TaskConcept(
            id: "medication",
            asks: #"\b(med|meds|medication|medications|medicine|medicines|tablets?|prescription|blister pack|dose|doses)\b"#,
            label: #"\b(medication|medicine|meds|blister pack|prescription|dose|doses)\b"#,
            noun: "medication"
        ),
        TaskConcept(
            id: "wound-treatment",
            precise: true,
            asks: #"\b(change|changing|treat|treating|redress|redressing|clean|cleaning)\b[^?]*\b(wound|dressing)\b"#,
            label: #"\b(change|treat|redress|clean)\b[^.]*\b(wound|dressing)\b"#,
            noun: "changing or treating a wound dressing",
            related: "wound-dressing"
        ),
        TaskConcept(
            id: "wound-dressing",
            precise: true,
            asks: #"\bwound\b|\bwound[- ]care\b"#,
            label: #"\bwound\b"#,
            noun: "wound care"
        ),
        TaskConcept(
            id: "personal-dressing",
            precise: true,
            asks: #"\b(dress|dressing|dressed)\b[^?]*\b(patient|client|person|them|him|her)\b|\b(get|getting|help(ing)? (them|him|her)) dressed\b|\bchange of clothes\b|\bpersonal dressing\b"#,
            label: #"\b(washing and dressing|change of clothes|get(ting)? dressed)\b"#,
            noun: "personal dressing"
        ),
        TaskConcept(
            id: "washing",
            asks: #"\b(wash|washing|washed|bathe|bathing|bath|shower|showering|personal care)\b"#,
            label: #"\b(wash|washing|bath|bathing|shower|personal care)\b"#,
            noun: "washing"
        ),
        TaskConcept(
            id: "feeding",
            precise: true,
            asks: #"\b(feed|feeding|fed|assist(ing)? with (eating|meals?)|help (them|him|her) eat|spoon)\b"#,
            label: #"\b(feed|feeding|assist[^.]*eating|spoon)\b"#,
            noun: "feeding a client directly",
            related: "food-preparation"
        ),
        TaskConcept(
            id: "food-preparation",
            asks: #"\b(food|meal|meals|breakfast|lunch|dinner|drink|drinks|cook|cooking|prepare|preparing)\b"#,
            label: #"\b(breakfast|meal|hot drink|food|cook)\b"#,
            noun: "preparing food or drink"
        ),
        TaskConcept(
            id: "walking",
            asks: #"\b(walk|walks|walking|walked|hallway|corridor|circuit|stroll|mobilit)\b"#,
            label: #"\b(walk|walking|hallway|circuit)\b"#,
            noun: "walking"
        ),
        TaskConcept(
            id: "exercise",
            asks: #"\b(exercise|exercises|exercising|seated exercises)\b"#,
            label: #"\b(exercise|exercises)\b"#,
            noun: "exercise"
        ),
        TaskConcept(
            id: "contact-task",
            asks: #"\b(ring|ringing|call|calling|phone|phoning|contact|contacting)\b"#,
            label: #"\b(ring|call|phone|contact)\b"#,
            noun: "making contact"
        ),
        TaskConcept(
            id: "equipment",
            asks: #"\b(equipment|alarm|pendant|rail|frame|jug|check(ing)? the)\b"#,
            label: #"\b(alarm|pendant|rail|frame|jug|bin)\b"#,
            noun: "an equipment check"
        ),
        TaskConcept(
            id: "records",
            asks: #"\b(record|records|recording|log|logging|note|notes|review|reviewing|paperwork|diaris)\b"#,
            label: #"\b(record|log|note|notes|review|diaris)\b"#,
            noun: "recording or reviewing"
        )
    ]

    static func concept(id: String) -> TaskConcept? {
        all.first { $0.id == id }
    }

    /// The concept a question is asking about, most specific first.
    ///
    /// `preciseOnly` restricts the search to the concepts that exist to tell
    /// look-alike actions apart. Those must be consulted before a literal word
    /// search, which would happily answer "dress the patient" with a wound.
    static func resolve(_ question: String, preciseOnly: Bool = false) -> TaskConcept? {
        all.first { concept in
            (!preciseOnly || concept.precise) && matches(concept.asks, question)
        }
    }

    /// Every recorded task matching a concept, across the round.
    static func tasks(in visits: [Visit], for concept: TaskConcept?) -> [TaskMatch] {
        guard let concept else { return [] }

        return AssistantQueries.allVisits(visits).flatMap { visit in
            visit.tasks
                .filter { matches(concept.label, "\($0.title) \($0.detail ?? "")") }
                .map { TaskMatch(visit: visit, task: $0) }
        }
    }

    static func related(to concept: TaskConcept?) -> TaskConcept? {
        guard let id = concept?.related else { return nil }
        return self.concept(id: id)
    }

    /// "Any dressing tasks?" without saying which kind. Two unrelated jobs share
    /// the word, so the honest reading is that the question has not chosen.
    static func isVagueDressing(_ question: String) -> Bool {
        matches(#"\bdress(ing|ings)?\b"#, question)
            && !matches(#"\bwound\b"#, question)
            && !matches(#"\b(patient|client|person|them|him|her|clothes|personal)\b"#, question)
    }

    static func dressingCategories(in visits: [Visit]) -> (personal: [TaskMatch], wound: [TaskMatch]) {
        (
            tasks(in: visits, for: concept(id: "personal-dressing")),
            tasks(in: visits, for: concept(id: "wound-dressing"))
        )
    }

    private static func matches(_ pattern: String, _ text: String) -> Bool {
        text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }
}
