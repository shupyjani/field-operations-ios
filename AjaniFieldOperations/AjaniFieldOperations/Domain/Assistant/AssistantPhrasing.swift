import Foundation

/// Turning facts into sentences.
///
/// Separate from the selectors so an answer's wording can be adjusted without
/// touching what it counted, and separate from the screen so the same sentence
/// is produced whether it is read aloud or displayed.
nonisolated enum AssistantPhrasing {
    /// "a, b and c"
    static func list(_ items: [String]) -> String {
        switch items.count {
        case 0: return ""
        case 1: return items[0]
        default: return items.dropLast().joined(separator: ", ") + " and " + (items.last ?? "")
        }
    }

    static func names(_ visits: [Visit]) -> String {
        list(visits.map(\.clientName))
    }

    /// "1 visit" / "3 visits"
    static func plural(_ count: Int, _ singular: String, _ plural: String? = nil) -> String {
        let word = count == 1 ? singular : (plural ?? singular + "s")
        return "\(count) \(word)"
    }

    static func window(_ visit: Visit) -> String {
        VisitFormatting.window(from: visit.scheduledStart, to: visit.scheduledEnd)
    }

    /// "Priya Raman, 9:40–10:40 (Arrived)"
    static func describe(_ visit: Visit) -> String {
        "\(visit.clientName), \(window(visit)) (\(visit.status.title))"
    }

    /// "Priya Raman — Check wound dressing (unchecked)"
    static func describe(_ match: TaskMatch) -> String {
        var text = "\(match.visit.clientName) — \(match.task.title) (\(match.task.isComplete ? "done" : "unchecked"))"
        if let detail = match.task.detail {
            text += " (\(detail))"
        }
        return text
    }

    static func minutes(_ count: Int) -> String {
        VisitFormatting.duration(minutes: count)
    }
}
