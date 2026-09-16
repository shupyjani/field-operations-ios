import Foundation

/// Who, if anyone, a question is about.
nonisolated enum PersonMatch: Hashable, Sendable {
    /// Exactly one person fits.
    case one(Visit)
    /// Two or more could equally have been meant.
    case ambiguous([Visit])
    /// A name-shaped word that is nobody on this round.
    case unknown(String)
}

nonisolated enum AssistantPeople {
    /// Words that look like names but never are.
    private static let notNames: Set<String> = [
        "the", "and", "for", "with", "any", "all", "who", "what", "which", "how",
        "many", "much", "does", "did", "has", "have", "had", "are", "was", "were",
        "visit", "visits", "task", "tasks", "client", "clients", "patient",
        "patients", "today", "next", "last", "first", "second", "third", "this",
        "that", "these", "those", "planned", "completed", "cancelled", "arrived",
        "route", "active", "priority", "remaining", "left", "tell", "show", "find",
        "about", "from", "into", "need", "needs", "time", "when", "where", "why",
        "can", "cannot", "should", "would", "could", "please", "round", "shift",
        "assistant", "app", "demo", "reset", "status", "note", "notes", "address",
        "related", "similar", "other", "still", "been", "done", "more", "than",
        "their", "them", "they", "his", "her", "she", "him", "you", "your", "mine"
    ]

    private static func parts(_ visit: Visit) -> (first: String, last: String) {
        let pieces = visit.clientName.lowercased().split(separator: " ").map(String.init)
        return (pieces.first ?? "", pieces.count > 1 ? (pieces.last ?? "") : "")
    }

    private static func candidateWords(_ question: String) -> [String] {
        let lowered = question.lowercased()
        let found = lowered.split { !($0.isLetter || $0 == "'" || $0 == "\u{2019}" || $0 == "-") }
            .map(String.init)

        return found
            .map { word -> String in
                var trimmed = word
                for suffix in ["'s", "\u{2019}s"] where trimmed.hasSuffix(suffix) {
                    trimmed = String(trimmed.dropLast(suffix.count))
                }
                return trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "'\u{2019}-"))
            }
            .filter { $0.count >= 3 && !notNames.contains($0) }
    }

    /// Who a question is about, or `nil` when it names no one.
    static func recognise(_ question: String, in visits: [Visit]) -> PersonMatch? {
        let asked = question.lowercased()
        guard !asked.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }

        // Whole name first: the least ambiguous thing anyone can type.
        let byFullName = visits.filter { visit in
            contains(word: visit.clientName.lowercased(), in: asked)
        }
        if byFullName.count == 1 { return .one(byFullName[0]) }

        let words = candidateWords(asked)
        guard !words.isEmpty else { return nil }

        // Exact first name or surname.
        let exact = visits.filter { visit in
            let name = parts(visit)
            return words.contains(name.first) || (!name.last.isEmpty && words.contains(name.last))
        }
        if exact.count == 1 { return .one(exact[0]) }

        // A missing apostrophe is considered only before a possessible app noun,
        // so an exact name — including one that already ends in s — always wins.
        let possessive = visits.filter { visit in
            let name = parts(visit)
            return [visit.clientName.lowercased(), name.first, name.last]
                .filter { !$0.isEmpty }
                .contains { candidate in
                    let pattern = "\\b\(NSRegularExpression.escapedPattern(for: candidate))s(?=\\s+(?:(?:remaining|recorded|unchecked|checked)\\s+)?(?:tasks?|visits?|checklist|notes?|address|walk|exercises?)\\b)"
                    return asked.range(of: pattern, options: [.regularExpression]) != nil
                }
        }
        if possessive.count == 1 { return .one(possessive[0]) }
        if possessive.count > 1 || exact.count > 1 {
            return .ambiguous(exact.isEmpty ? possessive : exact)
        }

        // A name-shaped word that is nobody, reported only when the wording
        // genuinely proposes a person. That is a question of grammatical
        // position rather than vocabulary: asking whether a stop-list contains
        // "related" or "similar" is a losing game.
        guard let proposed = words.first(where: { proposesName($0, in: question) }) else { return nil }
        return .unknown(proposed.prefix(1).uppercased() + proposed.dropFirst())
    }

    private static func proposesName(_ word: String, in original: String) -> Bool {
        let escaped = NSRegularExpression.escapedPattern(for: word)

        let positions = [
            "\\b(called|named)\\s+\(escaped)\\b",
            "\\b\(escaped)['\u{2019}]s\\b",
            "\\bis\\s+\(escaped)\\s+(on|in)\\s+(my|the)\\b",
            // Introduced the way a person is, or heading a run of two
            // capitalised words, which is what a full name looks like.
            "\\b(about|have|got|see|seeing|visit|visiting|with|meet|meeting|is|was|does|did)\\s+\(escaped)\\b",
            "\\b\(escaped)\\s+[A-Z][a-z]+"
        ]

        // The first three are case-insensitive; the last two need capitalisation
        // to carry any weight at all.
        for (index, pattern) in positions.enumerated() {
            let options: String.CompareOptions = index < 3
                ? [.regularExpression, .caseInsensitive]
                : [.regularExpression]
            let probe = index < 3 ? pattern : pattern.replacingOccurrences(
                of: escaped,
                with: escaped.prefix(1).uppercased() + escaped.dropFirst()
            )
            if original.range(of: probe, options: options) != nil { return true }
        }

        return false
    }

    private static func contains(word: String, in text: String) -> Bool {
        let pattern = "\\b\(NSRegularExpression.escapedPattern(for: word))\\b"
        return text.range(of: pattern, options: [.regularExpression]) != nil
    }
}
