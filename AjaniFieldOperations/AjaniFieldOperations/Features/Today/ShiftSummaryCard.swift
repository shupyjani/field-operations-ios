import SwiftUI

struct ShiftSummaryCard: View {
    let greeting: String
    let worker: Worker
    let shift: Shift
    let progress: ShiftProgress

    var body: some View {
        VStack(alignment: .leading, spacing: AjaniTheme.Spacing.l) {
            HStack(alignment: .top, spacing: AjaniTheme.Spacing.m) {
                VStack(alignment: .leading, spacing: AjaniTheme.Spacing.xs) {
                    Text("\(greeting), \(worker.firstName)")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(AjaniTheme.Palette.textPrimary)
                    Text(VisitFormatting.fullDate(shift.date))
                        .font(.subheadline)
                        .foregroundStyle(AjaniTheme.Palette.textSecondary)
                }
                Spacer(minLength: AjaniTheme.Spacing.s)
                InitialsAvatar(initials: worker.initials)
            }
            .accessibilityElement(children: .combine)

            // Side by side while both fit; stacked once the text outgrows the row.
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: AjaniTheme.Spacing.l) {
                    shiftRow
                    roundRow
                }
                VStack(alignment: .leading, spacing: AjaniTheme.Spacing.m) {
                    shiftRow
                    roundRow
                }
            }

            Divider()
                .overlay(AjaniTheme.Palette.separator)

            VStack(alignment: .leading, spacing: AjaniTheme.Spacing.s) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Shift progress")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AjaniTheme.Palette.textPrimary)
                    Spacer()
                    Text("\(progress.percentage)%")
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(AjaniTheme.Palette.primary)
                }
                AjaniProgressBar(fraction: progress.fraction)
                Text("\(progress.completed) of \(progress.total) visits complete · \(progress.remaining) remaining")
                    .font(.footnote)
                    .foregroundStyle(AjaniTheme.Palette.textSecondary)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Shift progress")
            .accessibilityValue("\(progress.completed) of \(progress.total) visits complete, \(progress.remaining) remaining")
        }
        .ajaniCard(padding: AjaniTheme.Spacing.xl)
    }

    private var shiftRow: some View {
        DetailRow(
            label: "Shift",
            value: VisitFormatting.window(from: shift.start, to: shift.end),
            symbolName: "clock"
        )
    }

    private var roundRow: some View {
        DetailRow(label: "Round", value: shift.region, symbolName: "map")
    }
}

struct InitialsAvatar: View {
    let initials: String

    /// Grows with the text so the initials never clip out of the circle.
    @ScaledMetric(relativeTo: .headline) private var size: CGFloat = 44

    var body: some View {
        Text(initials)
            .font(.headline)
            .foregroundStyle(AjaniTheme.Palette.primary)
            .frame(width: size, height: size)
            .background(Circle().fill(AjaniTheme.Palette.primarySoft))
            .accessibilityHidden(true)
    }
}

#Preview {
    ShiftSummaryCard(
        greeting: "Good morning",
        worker: DemoFieldData.worker,
        shift: DemoFieldData.shift(on: .now),
        progress: ShiftProgress(completed: 2, total: 7)
    )
    .padding()
    .frame(maxHeight: .infinity)
    .background(AjaniTheme.Palette.canvas)
}
