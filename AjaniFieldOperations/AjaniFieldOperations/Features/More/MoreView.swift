import SwiftUI

struct MoreView: View {
    @Environment(FieldOperationsStore.self) private var store

    @State private var isConfirmingReset = false

    var body: some View {
        @Bindable var store = store

        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AjaniTheme.Spacing.l) {
                    profileCard

                    VStack(alignment: .leading, spacing: AjaniTheme.Spacing.m) {
                        SectionHeader(title: "Preferences")

                        Toggle(isOn: $store.showsCompletedVisitsOnToday) {
                            preferenceLabel(
                                title: "Show completed visits on Today",
                                detail: "Keeps finished calls in the schedule list."
                            )
                        }
                        .frame(minHeight: AjaniTheme.Layout.minimumTapTarget)

                        Divider().overlay(AjaniTheme.Palette.separator)

                        Toggle(isOn: $store.confirmsVisitCompletion) {
                            preferenceLabel(
                                title: "Confirm before completing a visit",
                                detail: "Asks for confirmation before a visit is closed."
                            )
                        }
                        .frame(minHeight: AjaniTheme.Layout.minimumTapTarget)
                    }
                    .tint(AjaniTheme.Palette.primary)
                    .ajaniCard()

                    // Under a heading that already reads Application, the product's
                    // own symbol and name are the whole of what the card says.
                    VStack(alignment: .leading, spacing: AjaniTheme.Spacing.m) {
                        SectionHeader(title: "Application")
                        AppIdentityRow(name: AppInfo.displayName)
                    }
                    .ajaniCard()

                    // Last, because restoring the round is a demonstration utility
                    // rather than part of the application's own identity.
                    VStack(alignment: .leading, spacing: AjaniTheme.Spacing.m) {
                        SectionHeader(
                            title: "Demonstration round",
                            subtitle: "Restores the original seven visits, their checklists and both preferences."
                        )

                        Button("Reset demonstration round") {
                            isConfirmingReset = true
                        }
                        .buttonStyle(AjaniQuietButtonStyle())
                        .accessibilityIdentifier(AccessibilityID.moreResetAction)
                    }
                    .ajaniCard()
                }
                .padding(AjaniTheme.Spacing.l)
            }
            .background(AjaniTheme.Palette.canvas)
            .scrollBounceBehavior(.basedOnSize)
            .navigationTitle("More")
            .confirmationDialog(
                "Reset the demonstration round?",
                isPresented: $isConfirmingReset,
                titleVisibility: .visible
            ) {
                Button("Reset round", role: .destructive) {
                    store.reset()
                }
                .accessibilityIdentifier(AccessibilityID.moreResetConfirm)
                Button("Keep current round", role: .cancel) {}
            } message: {
                Text("Every status, checklist and cancellation returns to how the round started.")
            }
        }
    }

    private var profileCard: some View {
        VStack(alignment: .leading, spacing: AjaniTheme.Spacing.l) {
            HStack(spacing: AjaniTheme.Spacing.m) {
                InitialsAvatar(initials: store.worker.initials)
                VStack(alignment: .leading, spacing: 2) {
                    Text(store.worker.fullName)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(AjaniTheme.Palette.textPrimary)
                    Text(store.worker.role)
                        .font(.subheadline)
                        .foregroundStyle(AjaniTheme.Palette.textSecondary)
                }
            }
            .accessibilityElement(children: .combine)

            Divider().overlay(AjaniTheme.Palette.separator)

            DetailRow(label: "Team", value: store.worker.team, symbolName: "person.2")
            DetailRow(label: "Staff reference", value: store.worker.staffReference, symbolName: "person.text.rectangle")
            DetailRow(label: "Round", value: store.shift.region, symbolName: "map")
        }
        .ajaniCard(padding: AjaniTheme.Spacing.xl)
    }

    private func preferenceLabel(title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.body)
                .foregroundStyle(AjaniTheme.Palette.textPrimary)
            Text(detail)
                .font(.footnote)
                .foregroundStyle(AjaniTheme.Palette.textSecondary)
        }
    }
}

#Preview {
    MoreView()
        .environment(FieldOperationsStore())
}
