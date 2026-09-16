import Foundation
import Observation

/// One turn of the conversation.
nonisolated struct AssistantMessage: Identifiable, Hashable, Sendable {
    enum Role: String, Hashable, Sendable {
        case user
        case assistant
    }

    let id: Int
    let role: Role
    let text: String
    /// Set on assistant messages only, so a later live reply never relabels an
    /// earlier built-in one.
    let source: AssistantSource?
}

/// The assistant conversation, and the lifecycle of the question in flight.
///
/// Reads the round from the store and never writes to it: the assistant is a
/// reader, and that is enforced by it holding no mutating reference at all.
@Observable
@MainActor
final class AssistantConversation {
    enum Status: Hashable, Sendable {
        case idle
        case thinking
    }

    private(set) var messages: [AssistantMessage] = []
    private(set) var status: Status = .idle

    /// What the last answer named, so a follow-up has a referent.
    private(set) var selection: AssistantSelection?

    /// Bumped by every ask and matched by every reply, so an answer can only ever
    /// land on the question that asked for it. A request still in flight when the
    /// conversation is cleared carries an identifier the fresh conversation has
    /// never issued, and is dropped.
    private var requestID = 0
    private var nextMessageID = 0

    private let provider: AssistantProviding?

    init(provider: AssistantProviding? = nil) {
        self.provider = provider
    }

    var latestReplySource: AssistantSource? {
        messages.last { $0.role == .assistant }?.source
    }

    var isEmpty: Bool { messages.isEmpty }

    /// Asks a question about the round as it currently stands.
    ///
    /// The deterministic answer is computed first, before anything could leave
    /// the device. A boundary answer — clinical, disclosure or a request to act —
    /// is returned immediately and no provider is ever asked to refuse it.
    func ask(_ question: String, round: AssistantRound) async {
        let asked = String(
            question.trimmingCharacters(in: .whitespacesAndNewlines).prefix(AssistantCopy.messageLimit)
        )
        guard !asked.isEmpty, status != .thinking else { return }

        requestID += 1
        let issued = requestID

        append(role: .user, text: asked, source: nil)
        status = .thinking

        // The question before this one travels with the context, so a question
        // about the exchange is answered from the exchange itself.
        var carried = selection ?? AssistantSelection()
        carried.previousQuestion = messages.dropLast().last { $0.role == .user }?.text

        let local = LocalAssistant(round: round, context: carried).answer(asked)

        if local.isBoundary {
            // Answered here, and the conversation's referent is deliberately left
            // as it was: a refused request is not a new subject.
            deliver(
                AssistantReply(text: local.text, source: .builtIn, kind: local.kind, selection: selection),
                for: issued
            )
            return
        }

        guard let provider else {
            deliver(
                AssistantReply(text: local.text, source: .builtIn, kind: local.kind, selection: local.selection),
                for: issued
            )
            return
        }

        let history = messages.dropLast().map {
            AssistantHistoryEntry(role: $0.role.rawValue, text: $0.text)
        }
        // The selection the built-in answer resolved travels with the round, so
        // a provider reads the same set this question was answered against —
        // including a reference the question itself only pointed at.
        let remote = await provider.reply(
            to: asked,
            history: Array(history),
            snapshot: AssistantSnapshot(round: round, selection: local.selection)
        )

        // The built-in answer was computed before the request went out, so a
        // provider that fails costs nothing.
        let reply = remote.map {
            AssistantReply(text: $0, source: .live, kind: local.kind, selection: local.selection)
        } ?? AssistantReply(text: local.text, source: .builtIn, kind: local.kind, selection: local.selection)

        deliver(reply, for: issued)
    }

    /// Clears the conversation and invalidates anything in flight.
    func clear() {
        messages = []
        status = .idle
        selection = nil
        // A reply already on its way carries an identifier this conversation has
        // now moved past, so it can never repopulate what was just cleared.
        requestID += 1
    }

    // MARK: - Delivery

    private func deliver(_ reply: AssistantReply, for issued: Int) {
        // Not the question that is outstanding — a clear, or a newer ask, has
        // moved on since. Nothing is appended.
        guard issued == requestID, status == .thinking else { return }

        append(role: .assistant, text: reply.text, source: reply.source)
        selection = reply.selection
        status = .idle
    }

    private func append(role: AssistantMessage.Role, text: String, source: AssistantSource?) {
        nextMessageID += 1
        messages.append(AssistantMessage(id: nextMessageID, role: role, text: text, source: source))

        if messages.count > AssistantCopy.historyLimit {
            messages.removeFirst(messages.count - AssistantCopy.historyLimit)
        }
    }
}
