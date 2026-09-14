import SwiftUI

/// The one question a visit workflow is asking, if any.
///
/// Built from the store rather than presented as three competing alerts: the
/// store has already decided that at most one applies, so the interface only has
/// to say it. Keeping it to a single presentation is also what stops SwiftUI
/// arbitrating between several modifiers on the same view and clearing a pending
/// question before it has been shown.
private enum WorkflowQuestion: Identifiable {
    case blocked(BlockedTransition)
    case returnToPlanned(Visit.ID)
    case completion(CompletionPrompt)

    var id: String {
        switch self {
        case .blocked(let blocked): "blocked-\(blocked.attemptedVisitID)"
        case .returnToPlanned(let id): "return-\(id)"
        case .completion(let prompt): "completion-\(prompt.visitID)-\(prompt.outstandingCount)"
        }
    }
}

private struct VisitWorkflowPromptsModifier: ViewModifier {
    @Environment(FieldOperationsStore.self) private var store

    func body(content: Content) -> some View {
        content
            .alert(
                title,
                isPresented: questionBinding,
                presenting: question
            ) { question in
                actions(for: question)
            } message: { question in
                Text(message(for: question))
            }
            .sheet(isPresented: cancelBinding) {
                if let id = store.pendingCancelID, let visit = store.visit(id: id) {
                    CancelVisitSheet(
                        visit: visit,
                        onCancelVisit: { reason, note in
                            store.cancelVisit(id: visit.id, reason: reason, note: note)
                        },
                        onDismiss: { store.dismissCancellation() }
                    )
                }
            }
    }

    // MARK: - The question

    private var question: WorkflowQuestion? {
        if let blocked = store.blockedTransition { return .blocked(blocked) }
        if let id = store.pendingReturnID { return .returnToPlanned(id) }
        if let prompt = store.pendingCompletion { return .completion(prompt) }
        return nil
    }

    private var questionBinding: Binding<Bool> {
        Binding(
            get: { question != nil },
            set: { presented in
                guard !presented else { return }
                store.dismissBlockedTransition()
                store.dismissReturnToPlanned()
                store.dismissCompletionPrompt()
            }
        )
    }

    @ViewBuilder
    private func actions(for question: WorkflowQuestion) -> some View {
        switch question {
        case .blocked:
            Button("Stay here", role: .cancel) { store.dismissBlockedTransition() }

        case .returnToPlanned(let id):
            Button("Return to Planned") { store.returnToPlanned(id: id) }
                .accessibilityIdentifier(AccessibilityID.returnConfirm)
            Button("Keep En route", role: .cancel) { store.dismissReturnToPlanned() }

        case .completion(let prompt):
            Button(completionConfirmLabel(prompt)) {
                store.advanceStatus(of: prompt.visitID, confirmed: true)
            }
            .accessibilityIdentifier(AccessibilityID.completionConfirm)
            Button("Keep in progress", role: .cancel) { store.dismissCompletionPrompt() }
        }
    }

    private var title: String {
        switch question {
        case .blocked(let blocked):
            let active = store.visit(id: blocked.activeVisitID)?.clientName ?? "A visit"
            return "\(active) is still active"

        case .returnToPlanned(let id):
            let name = store.visit(id: id)?.clientName ?? "this visit"
            return "Return \(name) to Planned?"

        case .completion(let prompt):
            switch prompt.reason {
            case .outstandingTasks:
                return prompt.outstandingCount == 1
                    ? "1 task is still outstanding"
                    : "\(prompt.outstandingCount) tasks are still outstanding"
            case .preference:
                return "Complete this visit?"
            }

        case nil:
            return ""
        }
    }

    private func message(for question: WorkflowQuestion) -> String {
        switch question {
        case .blocked(let blocked):
            let active = store.visit(id: blocked.activeVisitID)?.clientName ?? "that visit"
            let attempted = store.visit(id: blocked.attemptedVisitID)?.clientName ?? "another"
            return "Only one visit can be active at a time. Complete or cancel \(active)'s visit before starting \(attempted)."

        case .returnToPlanned:
            return "This releases the active visit so another visit can be started."

        case .completion(let prompt):
            guard let visit = store.visit(id: prompt.visitID) else { return "" }
            switch prompt.reason {
            case .outstandingTasks:
                let noun = prompt.outstandingCount == 1 ? "that task" : "those tasks"
                return "Review the checklist for \(visit.clientName), or complete this visit with \(noun) outstanding."
            case .preference:
                let window = VisitFormatting.spokenWindow(from: visit.scheduledStart, to: visit.scheduledEnd)
                return "\(visit.clientName), \(window). Once a visit is completed its status cannot be changed again."
            }
        }
    }

    private func completionConfirmLabel(_ prompt: CompletionPrompt) -> String {
        switch prompt.reason {
        case .outstandingTasks:
            return prompt.outstandingCount == 1
                ? "Complete with task outstanding"
                : "Complete with tasks outstanding"
        case .preference:
            return "Complete visit"
        }
    }

    // MARK: - Cancellation

    private var cancelBinding: Binding<Bool> {
        Binding(
            get: { store.pendingCancelID != nil },
            set: { if !$0 { store.dismissCancellation() } }
        )
    }
}

extension View {
    /// Attach once per presenting context. The store decides which question applies.
    func visitWorkflowPrompts() -> some View {
        modifier(VisitWorkflowPromptsModifier())
    }
}
