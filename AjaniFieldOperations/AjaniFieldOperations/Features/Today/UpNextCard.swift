import SwiftUI

struct UpNextCard: View {
    let visit: Visit

    var body: some View {
        VStack(alignment: .leading, spacing: AjaniTheme.Spacing.l) {
            HStack(alignment: .firstTextBaseline) {
                Text(heading)
                    .font(.footnote.weight(.semibold))
                    .textCase(.uppercase)
                    .kerning(0.6)
                    .foregroundStyle(AjaniTheme.Palette.primary)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                StatusBadge(status: visit.status)
            }

            NavigationLink(value: visit.id) {
                VStack(alignment: .leading, spacing: AjaniTheme.Spacing.s) {
                    Text(visit.clientName)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(AjaniTheme.Palette.textPrimary)

                    HStack(spacing: AjaniTheme.Spacing.s) {
                        Text(visit.visitType)
                            .font(.subheadline)
                            .foregroundStyle(AjaniTheme.Palette.textSecondary)
                        if visit.priority == .priority {
                            PriorityBadge()
                        }
                    }

                    DetailRow(
                        label: "Scheduled",
                        value: "\(VisitFormatting.window(from: visit.scheduledStart, to: visit.scheduledEnd)) · \(VisitFormatting.duration(minutes: visit.scheduledDurationMinutes))",
                        symbolName: "clock"
                    )

                    DetailRow(
                        label: "Location",
                        value: visit.location.singleLineAddress,
                        symbolName: "mappin.and.ellipse"
                    )
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityIdentifier(AccessibilityID.todayUpNextVisit)
            .accessibilityLabel("\(visit.clientName), \(visit.visitType), \(VisitFormatting.spokenWindow(from: visit.scheduledStart, to: visit.scheduledEnd)), \(visit.location.singleLineAddress)")
            .accessibilityHint("Opens the visit details")
            .accessibilityAddTraits(.isButton)

            VisitAdvanceButton(visit: visit, accessibilityIdentifier: AccessibilityID.todayUpNextAction)
        }
        .ajaniCard(padding: AjaniTheme.Spacing.xl)
    }

    private var heading: String {
        visit.status.isInProgress ? "In progress" : "Up next"
    }
}

#Preview {
    NavigationStack {
        UpNextCard(visit: DemoFieldData.visits(on: .now)[3])
            .padding()
            .frame(maxHeight: .infinity)
            .background(AjaniTheme.Palette.canvas)
            .environment(FieldOperationsStore())
    }
}
