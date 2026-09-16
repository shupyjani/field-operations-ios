import Foundation

/// Explaining the app's controls.
///
/// Every sentence describes a rule that exists in the domain, and the wording is
/// built from the same constants the interface uses, so the guidance cannot drift
/// away from the behaviour it describes. Nothing here performs an action: "how do
/// I complete a visit?" is answered, "complete it for me" is not.
nonisolated struct GuidanceEntry: Hashable, Sendable {
    let id: String
    let pattern: String
    let text: String
}

nonisolated enum AssistantGuidance {
    private static var reasons: String {
        let titles = CancellationReason.allCases.map(\.title)
        guard titles.count > 1 else { return titles.joined() }
        return titles.dropLast().joined(separator: ", ") + " and " + (titles.last ?? "")
    }

    private static var filters: String {
        VisitStatusFilter.allCases.map(\.title).joined(separator: ", ")
    }

    /// Ordered most specific first, because these questions overlap heavily.
    static var entries: [GuidanceEntry] {
        [
            GuidanceEntry(
                id: "open-visit",
                pattern: #"\bopen\b[^?]*\bvisit\b"#,
                text: "Open Today or Visits and select a visit to see its details. Visits also lets you search and filter the round."
            ),
            GuidanceEntry(
                id: "assistant-navigation",
                pattern: #"\bassistant\b|\bconversation\b|\bchat\b"#,
                text: "Open More and choose \u{201C}Open assistant\u{201D}. Use Back to leave it. Reopening retains the last \(AssistantCopy.historyLimit) messages; resetting the round clears them."
            ),
            GuidanceEntry(
                id: "task-lock",
                pattern: #"\btasks?\b[^?]*\blocked\b|\b(why|can'?t|cannot|unable)\b[^?]*\b(tick|ticking|check|edit|change|complete)\b[^?]*\btask"#,
                text: "Tasks can only be ticked once the visit is Arrived. Planned and En route checklists are locked; Completed and Cancelled checklists remain readable but cannot be edited."
            ),
            GuidanceEntry(
                id: "task-vs-visit",
                pattern: #"\b(difference|differ|versus|vs|rather than|not the same)\b[^?]*\btask"#,
                text: "Ticking a task records one piece of work. Completing the visit closes the record and moves it to Completed with the \u{201C}\(VisitStatus.arrived.advanceActionTitle ?? "")\u{201D} button. They are separate: a visit can be completed with tasks still unticked, and ticking every task does not complete the visit on its own."
            ),
            GuidanceEntry(
                id: "outstanding-warning",
                pattern: #"\b(outstanding|unticked|unchecked|incomplete)\b[^?]*\b(task|warning|complete)|\bwhat happens\b[^?]*\boutstanding\b"#,
                text: "Completing a visit with unticked tasks raises a warning first, saying how many are outstanding. You can review the checklist or complete anyway — the tasks are left exactly as they were either way."
            ),
            GuidanceEntry(
                id: "complete-visit",
                pattern: #"\bhow (do|can) i\b[^?]*\bcomplete\b|\bcompleting a visit\b"#,
                text: "Open the visit and use \u{201C}\(VisitStatus.arrived.advanceActionTitle ?? "")\u{201D}. It only appears once the visit is Arrived, and completing is final — there is no control anywhere that reopens a completed visit."
            ),
            GuidanceEntry(
                id: "start-travel",
                pattern: #"\b(start|starting|begin|travel|travelling|en ?route|arrive|arriving|arrival)\b"#,
                text: "A visit moves one step at a time: \u{201C}\(VisitStatus.planned.advanceActionTitle ?? "")\u{201D} takes it from Planned to En route, \u{201C}\(VisitStatus.enRoute.advanceActionTitle ?? "")\u{201D} takes it to Arrived, and \u{201C}\(VisitStatus.arrived.advanceActionTitle ?? "")\u{201D} closes it. Steps cannot be skipped. En route can be returned to Planned with confirmation."
            ),
            GuidanceEntry(
                id: "one-active",
                pattern: #"\b(two|second|another|more than one|same time|at once|multiple)\b[^?]*\b(visit|active|travel)|\bone active\b"#,
                text: "Only one visit can be active at a time. Starting a second is refused while another is En route or Arrived, and the app offers to open the active visit instead."
            ),
            GuidanceEntry(
                id: "return-to-planned",
                pattern: #"\b(return|revert|undo|go back|back to planned|redirect)\b"#,
                text: "Only an En route visit can be returned to Planned. Confirm the return and the visit keeps its tasks and every other field; only the status moves, which releases the active-visit lock. Arrived and Completed cannot be reversed."
            ),
            GuidanceEntry(
                id: "cancel",
                pattern: #"\bcancel"#,
                text: "Open a visit that is Planned or En route and choose \u{201C}Cancel visit\u{201D}. Pick a reason — \(reasons) — and add a note, which is required for \u{201C}Other\u{201D} and capped at \(CancellationRules.noteLimit) characters. Arrived, Completed and already cancelled visits cannot be cancelled, and cancelling never changes the checklist."
            ),
            GuidanceEntry(
                id: "read-only",
                pattern: #"\b(read[- ]only|locked|fixed|edit)\b[^?]*\b(completed|cancelled|closed)|\b(completed|cancelled)\b[^?]*\b(checklist|read|edit)\b"#,
                text: "Completed and Cancelled checklists stay readable but cannot be edited. The record of what was done is never hidden and never rewritten."
            ),
            GuidanceEntry(
                id: "show-completed",
                pattern: #"\b(hide|hiding|show|showing|display)\b[^?]*\bcompleted\b|\bshow completed\b"#,
                text: "More has a \u{201C}Show completed visits on Today\u{201D} preference. Turning it off hides completed visits from the Today list only — it changes nothing about the visits themselves, and the Visits tab still lists them."
            ),
            GuidanceEntry(
                id: "confirm-completion",
                pattern: #"\bconfirm"#,
                text: "More has a \u{201C}Confirm before completing a visit\u{201D} preference. With it on, completing a visit asks first. A visit with outstanding tasks asks anyway, whatever the preference says — the two questions never both appear for one tap."
            ),
            GuidanceEntry(
                id: "filters",
                pattern: #"\b(filter|filters|search|searching|find|look up|looking up)\b"#,
                text: "The Visits tab has a search field and the filters \(filters). Search matches the name, reference, service and address; the filters narrow by status. Tapping any visit opens its detail, and the back control returns to the list."
            ),
            GuidanceEntry(
                id: "reset",
                pattern: #"\breset\b|\bstart (over|again)\b"#,
                text: "More has a \u{201C}Reset demonstration round\u{201D} button. It restores the original round — statuses, checklists, cancellations, preferences and the assistant conversation all return to how they started."
            ),
            GuidanceEntry(
                id: "assistant",
                pattern: #"\b(assistant|this chat|conversation|you)\b[^?]*\b(work|do|keep|remember|navigat)|\bcan you (change|update|complete|cancel)\b"#,
                text: "The assistant reads the round and explains controls; it cannot change anything. The tabs stay usable while it is open, and the conversation is kept when you navigate away and come back — the last \(AssistantCopy.historyLimit) messages of it. Resetting the round clears it."
            )
        ]
    }

    /// The guidance a question asks for, or `nil`.
    static func find(_ question: String) -> GuidanceEntry? {
        // Reversing a closed visit is asked about often and is not the same as
        // returning an En route visit, so it is answered before the table.
        if !matches(#"\bassistant\b"#, question),
           matches(#"\b(restore|reopen|undo|return|revert|untick)\b"#, question) {
            if matches(#"\btask\b"#, question) && matches(#"\b(closed|completed|cancelled)\b"#, question) {
                return GuidanceEntry(
                    id: "closed-task",
                    pattern: "",
                    text: "Completed and Cancelled visits have read-only checklists: tasks cannot be ticked or unticked. Resetting the round restores it entirely and clears the conversation."
                )
            }
            if matches(#"\b(cancelled|cancellation|completed|completion)\b"#, question) {
                let status = matches(#"\b(cancelled|cancellation)\b"#, question) ? "cancelled" : "Completed"
                return GuidanceEntry(
                    id: "restore-closed",
                    pattern: "",
                    text: "This app does not support restoring an individual \(status) visit to Planned. \u{201C}Return to Planned\u{201D} applies to an En route visit. Resetting the round restores it entirely and clears the conversation."
                )
            }
            if matches(#"\b(restore|reopen)\b"#, question) {
                return GuidanceEntry(
                    id: "restore",
                    pattern: "",
                    text: "An individual Completed or Cancelled visit cannot be reopened. \u{201C}Return to Planned\u{201D} applies only to an En route visit. Resetting the round restores it entirely and clears the conversation."
                )
            }
        }

        let table = entries
        // These outrank the general travel guidance, which would otherwise
        // answer a question about the one-active rule.
        for id in ["one-active", "return-to-planned", "cancel", "reset", "read-only", "confirm-completion"] {
            if let entry = table.first(where: { $0.id == id }), matches(entry.pattern, question) {
                return entry
            }
        }

        return table.first { matches($0.pattern, question) }
    }

    /// Controls the app deliberately does not have, answered plainly rather than
    /// with a search that finds nothing.
    static let absentControls: [GuidanceEntry] = [
        GuidanceEntry(
            id: "void",
            pattern: #"\bvoid(ing)?\b"#,
            text: "There is no Void workflow in this app. Planned and En route visits can be cancelled with a reason."
        ),
        GuidanceEntry(
            id: "appearance",
            pattern: #"\b(dark mode|light mode|theme|appearance|font size|colour scheme|color scheme)\b"#,
            text: "The app has no appearance setting — it follows the system. More holds two preferences only: showing completed visits on Today, and confirming before completing."
        ),
        GuidanceEntry(
            id: "external",
            pattern: #"\b(open|switch to|go to|launch)\b[^?]*\b(maps?|email|phone app|browser|another app|settings app)\b"#,
            text: "This app does not open anything outside itself. Every control you can see belongs to it."
        ),
        GuidanceEntry(
            id: "add",
            pattern: #"\b(add|create|book|schedule|new)\b[^?]*\b(visit|client|task)\b"#,
            text: "The round is fixed — there is no control for adding a visit, a client or a task. Resetting restores the original seven visits."
        )
    ]

    static func findAbsentControl(_ question: String) -> GuidanceEntry? {
        absentControls.first { matches($0.pattern, question) }
    }

    private static func matches(_ pattern: String, _ text: String) -> Bool {
        text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }
}
