import SwiftUI

extension VisitStatus {
    var tint: Color {
        switch self {
        case .planned: AjaniTheme.Palette.statusPlanned
        case .enRoute: AjaniTheme.Palette.statusEnRoute
        case .arrived: AjaniTheme.Palette.statusArrived
        case .completed: AjaniTheme.Palette.statusCompleted
        }
    }
}

struct StatusBadge: View {
    let status: VisitStatus

    var body: some View {
        Label {
            Text(status.title)
        } icon: {
            Image(systemName: status.symbolName)
        }
        .font(.footnote.weight(.semibold))
        .labelStyle(.titleAndIcon)
        .foregroundStyle(status.tint)
        .padding(.horizontal, AjaniTheme.Spacing.m)
        .padding(.vertical, AjaniTheme.Spacing.xs + 2)
        .background(
            Capsule().fill(status.tint.opacity(0.14))
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Status")
        .accessibilityValue(status.title)
    }
}

struct PriorityBadge: View {
    var body: some View {
        Text("Priority")
            .font(.footnote.weight(.semibold))
            .foregroundStyle(AjaniTheme.Palette.accent)
            .padding(.horizontal, AjaniTheme.Spacing.m)
            .padding(.vertical, AjaniTheme.Spacing.xs + 2)
            .background(Capsule().fill(AjaniTheme.Palette.accentSoft))
            .accessibilityLabel("Priority visit")
    }
}

#Preview {
    VStack(alignment: .leading, spacing: AjaniTheme.Spacing.m) {
        ForEach(VisitStatus.allCases, id: \.self) { status in
            StatusBadge(status: status)
        }
        PriorityBadge()
    }
    .padding()
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .ajaniCanvas()
}
