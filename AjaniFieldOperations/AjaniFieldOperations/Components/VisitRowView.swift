import SwiftUI

/// The visit card shared by the Today schedule and the Visits list.
struct VisitRowView: View {
    let visit: Visit

    var body: some View {
        NavigationLink(value: visit.id) {
            VStack(alignment: .leading, spacing: AjaniTheme.Spacing.s) {
                // Side by side while both fit; stacked once the time and badge
                // can no longer share a line.
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline) {
                        scheduleWindow
                        Spacer(minLength: AjaniTheme.Spacing.s)
                        StatusBadge(status: visit.status)
                    }
                    VStack(alignment: .leading, spacing: AjaniTheme.Spacing.s) {
                        scheduleWindow
                        StatusBadge(status: visit.status)
                    }
                }

                Text(visit.clientName)
                    .font(.headline)
                    .foregroundStyle(AjaniTheme.Palette.textPrimary)

                HStack(spacing: AjaniTheme.Spacing.s) {
                    Text(visit.visitType)
                        .font(.subheadline)
                        .foregroundStyle(AjaniTheme.Palette.textSecondary)
                    if visit.priority == .priority {
                        PriorityBadge()
                    }
                }

                Label(visit.location.singleLineAddress, systemImage: "mappin.and.ellipse")
                    .font(.footnote)
                    .foregroundStyle(AjaniTheme.Palette.textSecondary)
            }
            .ajaniCard()
            .contentShape(RoundedRectangle(cornerRadius: AjaniTheme.Radius.card, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityIdentifier(AccessibilityID.visitRow(visit.reference))
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(visit.status.title)
        .accessibilityHint("Opens the visit details")
        .accessibilityAddTraits(.isButton)
    }

    private var scheduleWindow: some View {
        Text(VisitFormatting.window(from: visit.scheduledStart, to: visit.scheduledEnd))
            .font(.subheadline.weight(.semibold))
            .monospacedDigit()
            .foregroundStyle(AjaniTheme.Palette.textSecondary)
    }

    private var accessibilityLabel: String {
        var parts = [
            visit.clientName,
            visit.visitType,
            VisitFormatting.spokenWindow(from: visit.scheduledStart, to: visit.scheduledEnd),
            visit.location.singleLineAddress
        ]
        if visit.priority == .priority {
            parts.insert("Priority visit", at: 1)
        }
        return parts.joined(separator: ", ")
    }
}

#Preview {
    NavigationStack {
        ScrollView {
            LazyVStack(spacing: AjaniTheme.Spacing.m) {
                ForEach(DemoFieldData.visits(on: .now)) { visit in
                    VisitRowView(visit: visit)
                }
            }
            .padding(AjaniTheme.Spacing.l)
        }
        .ajaniCanvas()
    }
}
