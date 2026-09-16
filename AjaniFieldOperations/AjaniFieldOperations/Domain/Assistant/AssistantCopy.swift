import Foundation

/// The assistant's fixed wording, kept in one place so the screen and the
/// answers cannot describe the assistant differently.
nonisolated enum AssistantCopy {
    static let title = "Ajani Assistant"

    static let disclosure = "Operational assistant. It cannot give clinical advice or update visits."

    static let welcome =
        "Ask about the round — the next visit, what is active, what is planned, or how a "
        + "control works. Try one of the questions below."

    /// Shown against a reply the deterministic assistant produced.
    static let builtInNotice = "Built-in guidance"

    /// Shown only against a reply that genuinely came from the provider.
    static let liveNotice = "AI response"

    static let suggestedQuestions = [
        "Who is my next visit?",
        "Which visit is currently active?",
        "Show my planned visits.",
        "Which visit is marked Priority?",
        "Find Ivor Bankole.",
        "What tasks remain for Priya Raman?",
        "How do I cancel a visit?",
        "What happens to progress when a visit is cancelled?"
    ]

    static let clinicalRefusal =
        "I cannot give clinical advice. For anything about a person\u{2019}s care — symptoms, "
        + "medication, treatment or an urgent concern — follow your organisation\u{2019}s policy "
        + "and its clinical escalation process, and contact the duty line or emergency "
        + "services as that policy requires."

    static let unsupported =
        "I couldn\u{2019}t find that in today\u{2019}s round. You can ask about a person, visit status, "
        + "task or cancellation."

    static let disclosureRefusal =
        "I do not have anything like that to share. I can only describe this "
        + "round and how the app\u{2019}s controls work."

    static let demographic =
        "The round does not record that. It holds each visit\u{2019}s person, service, schedule, "
        + "address, status, checklist and notes."

    static func notFoundPerson(_ name: String) -> String {
        "I can\u{2019}t find anyone called \(name) in today\u{2019}s round."
    }

    /// The longest question the assistant accepts, matching the endpoint contract.
    static let messageLimit = 500

    /// How much of the conversation is kept.
    static let historyLimit = 20
}
