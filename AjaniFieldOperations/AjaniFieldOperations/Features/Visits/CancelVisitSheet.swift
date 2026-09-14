import SwiftUI

/// Collects a reason, and a note where one is owed, before a visit is called off.
///
/// Validation is not duplicated here: the sentence comes from the same
/// `CancellationRules.validate` the store uses, so the sheet cannot allow
/// something the store would refuse, or refuse something it would allow.
struct CancelVisitSheet: View {
    let visit: Visit
    let onCancelVisit: (CancellationReason, String) -> Void
    let onDismiss: () -> Void

    @State private var reason: CancellationReason?
    @State private var note = ""

    /// What is still outstanding, or `nil` once the form may be submitted.
    ///
    /// The same rule the store enforces, so the button cannot offer something the
    /// store would refuse — and a cancellation is never one tap away from being
    /// recorded without a reason.
    private var requirement: String? {
        CancellationRules.validate(reason: reason, note: note)
    }

    private var noteRequired: Bool {
        reason?.requiresNote ?? false
    }

    private var remainingCharacters: Int {
        CancellationRules.noteLimit - note.trimmingCharacters(in: .whitespacesAndNewlines).count
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AjaniTheme.Spacing.l) {
                    // Says what is still needed while it is still needed, rather
                    // than only after a rejected tap.
                    if let requirement {
                        Label(requirement, systemImage: "exclamationmark.triangle.fill")
                            .font(.subheadline)
                            .foregroundStyle(AjaniTheme.Palette.statusCancelled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(AjaniTheme.Spacing.m)
                            .background(
                                RoundedRectangle(cornerRadius: AjaniTheme.Radius.inner, style: .continuous)
                                    .fill(AjaniTheme.Palette.statusCancelled.opacity(0.12))
                            )
                            .accessibilityIdentifier(AccessibilityID.cancelSheetRequirement)
                    }

                    reasonCard
                    noteCard
                }
                .padding(AjaniTheme.Spacing.l)
            }
            .background(AjaniTheme.Palette.canvas)
            .scrollBounceBehavior(.basedOnSize)
            .navigationTitle("Cancel visit")
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                actionBar
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Keep visit") { onDismiss() }
                }
            }
        }
    }

    private var reasonCard: some View {
        VStack(alignment: .leading, spacing: AjaniTheme.Spacing.m) {
            SectionHeader(
                title: "Reason",
                subtitle: "Why is \(visit.clientName)'s visit being cancelled?"
            )

            VStack(spacing: AjaniTheme.Spacing.s) {
                ForEach(CancellationReason.allCases) { option in
                    reasonRow(option)
                }
            }
        }
        .ajaniCard()
    }

    private func reasonRow(_ option: CancellationReason) -> some View {
        let isSelected = reason == option

        return Button {
            reason = option
        } label: {
            HStack(spacing: AjaniTheme.Spacing.m) {
                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? AjaniTheme.Palette.primary : AjaniTheme.Palette.textSecondary)
                Text(option.title)
                    .font(.body)
                    .foregroundStyle(AjaniTheme.Palette.textPrimary)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            }
            .padding(AjaniTheme.Spacing.m)
            .frame(minHeight: AjaniTheme.Layout.minimumTapTarget)
            .background(
                RoundedRectangle(cornerRadius: AjaniTheme.Radius.inner, style: .continuous)
                    .fill(AjaniTheme.Palette.surfaceMuted)
            )
            .contentShape(RoundedRectangle(cornerRadius: AjaniTheme.Radius.inner, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(AccessibilityID.cancelReason(option))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(option.title)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    private var noteCard: some View {
        VStack(alignment: .leading, spacing: AjaniTheme.Spacing.m) {
            SectionHeader(
                title: noteRequired ? "Operational note" : "Operational note (optional)",
                subtitle: noteRequired
                    ? "Required for \u{201C}Other\u{201D}. Up to \(CancellationRules.noteLimit) characters."
                    : "Up to \(CancellationRules.noteLimit) characters."
            )

            TextEditor(text: $note)
                .font(.body)
                .foregroundStyle(AjaniTheme.Palette.textPrimary)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 96)
                .padding(AjaniTheme.Spacing.s)
                .background(
                    RoundedRectangle(cornerRadius: AjaniTheme.Radius.inner, style: .continuous)
                        .fill(AjaniTheme.Palette.surfaceMuted)
                )
                .accessibilityIdentifier(AccessibilityID.cancelSheetNote)
                .accessibilityLabel("Operational note")

            Text(remainingCharacters >= 0
                 ? "\(remainingCharacters) characters remaining"
                 : "\(-remainingCharacters) characters over the limit")
                .font(.footnote)
                .foregroundStyle(remainingCharacters >= 0
                                 ? AjaniTheme.Palette.textSecondary
                                 : AjaniTheme.Palette.statusCancelled)
        }
        .ajaniCard()
    }

    private var actionBar: some View {
        Button("Cancel visit") { submit() }
            .buttonStyle(AjaniPrimaryButtonStyle())
            .disabled(requirement != nil)
            .accessibilityIdentifier(AccessibilityID.cancelSheetConfirm)
            // Says why it cannot be used yet, for a reader who cannot see the
            // requirement sitting above the form.
            .accessibilityHint(requirement ?? "")
            .padding(.horizontal, AjaniTheme.Spacing.l)
            .padding(.vertical, AjaniTheme.Spacing.m)
            .background(.bar)
    }

    private func submit() {
        // Checked again here: the button is disabled while anything is outstanding,
        // and the store refuses an invalid cancellation regardless.
        guard requirement == nil, let reason else { return }
        onCancelVisit(reason, note)
    }
}

#Preview {
    CancelVisitSheet(
        visit: DemoFieldData.visits(on: .now)[3],
        onCancelVisit: { _, _ in },
        onDismiss: {}
    )
}
