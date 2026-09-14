import SwiftUI

/// Moves a visit to the next stage of its journey. Renders nothing once the visit
/// is closed, so the interface never shows an action that cannot be taken.
///
/// The guarded decisions — one active visit, outstanding tasks, the confirmation
/// preference — belong to the store. This only asks, and the store either applies
/// the step or raises the question that has to be answered first.
struct VisitAdvanceButton: View {
    let visit: Visit
    let accessibilityIdentifier: String

    @Environment(FieldOperationsStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if let title = visit.status.advanceActionTitle, let successor = visit.status.successor {
            Button(title) { advance() }
                .buttonStyle(AjaniPrimaryButtonStyle())
                .accessibilityIdentifier(accessibilityIdentifier)
                .accessibilityHint("Moves \(visit.clientName) to \(successor.title)")
        }
    }

    private func advance() {
        if reduceMotion {
            store.advanceStatus(of: visit.id)
        } else {
            withAnimation(.easeInOut(duration: 0.2)) {
                _ = store.advanceStatus(of: visit.id)
            }
        }
    }
}
