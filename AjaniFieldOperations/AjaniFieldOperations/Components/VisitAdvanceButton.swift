import SwiftUI

/// Moves a visit to the next stage of its journey. Renders nothing once the visit is complete,
/// so the interface never shows an action that cannot be taken.
struct VisitAdvanceButton: View {
    let visit: Visit
    let accessibilityIdentifier: String

    @Environment(FieldOperationsStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isConfirmingCompletion = false

    var body: some View {
        if let title = visit.status.advanceActionTitle, let successor = visit.status.successor {
            Button(title) {
                if successor == .completed && store.confirmsVisitCompletion {
                    isConfirmingCompletion = true
                } else {
                    advance()
                }
            }
            .buttonStyle(AjaniPrimaryButtonStyle())
            .accessibilityIdentifier(accessibilityIdentifier)
            .accessibilityHint("Moves \(visit.clientName) to \(successor.title)")
            .confirmationDialog(
                "Complete this visit?",
                isPresented: $isConfirmingCompletion,
                titleVisibility: .visible
            ) {
                Button("Complete visit") { advance() }
                Button("Keep in progress", role: .cancel) {}
            } message: {
                Text("\(visit.clientName), \(VisitFormatting.spokenWindow(from: visit.scheduledStart, to: visit.scheduledEnd))")
            }
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
