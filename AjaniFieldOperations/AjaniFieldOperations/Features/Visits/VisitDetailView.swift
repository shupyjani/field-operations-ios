import SwiftUI

struct VisitDetailView: View {
    let visitID: Visit.ID

    @Environment(FieldOperationsStore.self) private var store

    /// Note bullets track the note text rather than staying at a fixed size.
    @ScaledMetric(relativeTo: .subheadline) private var bulletSize: CGFloat = 5

    var body: some View {
        Group {
            if let visit = store.visit(id: visitID) {
                content(for: visit)
            } else {
                ContentUnavailableView(
                    "Visit unavailable",
                    systemImage: "questionmark.circle",
                    description: Text("This visit is no longer part of the current shift.")
                )
            }
        }
        .background(AjaniTheme.Palette.canvas)
        .navigationTitle("Visit")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func content(for visit: Visit) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AjaniTheme.Spacing.l) {
                headerCard(visit)
                scheduleCard(visit)
                locationCard(visit)
                tasksCard(visit)
                notesCard(visit)
            }
            .padding(AjaniTheme.Spacing.l)
        }
        .scrollBounceBehavior(.basedOnSize)
        .safeAreaInset(edge: .bottom) {
            actionBar(visit)
        }
    }

    private func headerCard(_ visit: Visit) -> some View {
        VStack(alignment: .leading, spacing: AjaniTheme.Spacing.m) {
            HStack(alignment: .firstTextBaseline) {
                Text(visit.reference)
                    .font(.footnote.weight(.semibold))
                    .monospaced()
                    .foregroundStyle(AjaniTheme.Palette.textSecondary)
                Spacer()
                StatusBadge(status: visit.status)
            }

            Text(visit.clientName)
                .font(.title2.weight(.semibold))
                .foregroundStyle(AjaniTheme.Palette.textPrimary)

            HStack(spacing: AjaniTheme.Spacing.s) {
                Text(visit.visitType)
                    .font(.subheadline)
                    .foregroundStyle(AjaniTheme.Palette.textSecondary)
                if visit.priority == .priority {
                    PriorityBadge()
                }
            }
        }
        .ajaniCard(padding: AjaniTheme.Spacing.xl)
    }

    private func scheduleCard(_ visit: Visit) -> some View {
        VStack(alignment: .leading, spacing: AjaniTheme.Spacing.m) {
            SectionHeader(title: "Time")
            DetailRow(
                label: "Scheduled",
                value: VisitFormatting.window(from: visit.scheduledStart, to: visit.scheduledEnd),
                symbolName: "clock"
            )
            DetailRow(
                label: "Planned duration",
                value: VisitFormatting.duration(minutes: visit.scheduledDurationMinutes),
                symbolName: "hourglass"
            )
            if visit.location.travelMinutes > 0 {
                DetailRow(
                    label: "Travel from previous visit",
                    value: VisitFormatting.duration(minutes: visit.location.travelMinutes),
                    symbolName: "car"
                )
            }
        }
        .ajaniCard()
    }

    private func locationCard(_ visit: Visit) -> some View {
        VStack(alignment: .leading, spacing: AjaniTheme.Spacing.m) {
            SectionHeader(title: "Location")
            DetailRow(label: "Address", value: visit.location.addressLine, symbolName: "house")
            DetailRow(label: "District", value: visit.location.district, symbolName: "map")
            DetailRow(label: "Postcode", value: visit.location.postcode, symbolName: "number")
        }
        .ajaniCard()
    }

    private func tasksCard(_ visit: Visit) -> some View {
        VStack(alignment: .leading, spacing: AjaniTheme.Spacing.m) {
            SectionHeader(
                title: "Tasks",
                subtitle: "\(visit.completedTaskCount) of \(visit.tasks.count) done"
            )
            VStack(spacing: AjaniTheme.Spacing.s) {
                ForEach(visit.tasks) { task in
                    TaskToggleRow(task: task, visitID: visit.id)
                }
            }
        }
        .ajaniCard()
    }

    private func notesCard(_ visit: Visit) -> some View {
        VStack(alignment: .leading, spacing: AjaniTheme.Spacing.m) {
            SectionHeader(title: "Operational notes")
            VStack(alignment: .leading, spacing: AjaniTheme.Spacing.s) {
                ForEach(visit.operationalNotes, id: \.self) { note in
                    HStack(alignment: .firstTextBaseline, spacing: AjaniTheme.Spacing.s) {
                        Circle()
                            .fill(AjaniTheme.Palette.accent)
                            .frame(width: bulletSize, height: bulletSize)
                            .accessibilityHidden(true)
                        Text(note)
                            .font(.subheadline)
                            .foregroundStyle(AjaniTheme.Palette.textPrimary)
                    }
                }
            }
        }
        .ajaniCard()
    }

    @ViewBuilder
    private func actionBar(_ visit: Visit) -> some View {
        VStack(spacing: AjaniTheme.Spacing.s) {
            if visit.status == .completed {
                Label("Visit completed", systemImage: "checkmark.circle.fill")
                    .font(.headline)
                    .foregroundStyle(AjaniTheme.Palette.statusCompleted)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: AjaniTheme.Layout.minimumTapTarget)
                    .accessibilityIdentifier(AccessibilityID.visitDetailCompletedNotice)
            } else {
                VisitAdvanceButton(
                    visit: visit,
                    accessibilityIdentifier: AccessibilityID.visitDetailPrimaryAction
                )
            }
        }
        .padding(.horizontal, AjaniTheme.Spacing.l)
        .padding(.vertical, AjaniTheme.Spacing.m)
        .background(.bar)
    }
}

private struct TaskToggleRow: View {
    let task: VisitTask
    let visitID: Visit.ID

    @Environment(FieldOperationsStore.self) private var store

    var body: some View {
        Button {
            store.setTask(task.id, isComplete: !task.isComplete, on: visitID)
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: AjaniTheme.Spacing.m) {
                Image(systemName: task.isComplete ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(task.isComplete ? AjaniTheme.Palette.statusCompleted : AjaniTheme.Palette.textSecondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(task.title)
                        .font(.body)
                        .foregroundStyle(AjaniTheme.Palette.textPrimary)
                        .strikethrough(task.isComplete, color: AjaniTheme.Palette.textSecondary)
                    if let detail = task.detail {
                        Text(detail)
                            .font(.footnote)
                            .foregroundStyle(AjaniTheme.Palette.textSecondary)
                    }
                }
                Spacer(minLength: 0)
            }
            .multilineTextAlignment(.leading)
            .padding(AjaniTheme.Spacing.m)
            .frame(minHeight: AjaniTheme.Layout.minimumTapTarget)
            .background(
                RoundedRectangle(cornerRadius: AjaniTheme.Radius.inner, style: .continuous)
                    .fill(AjaniTheme.Palette.surfaceMuted)
            )
            .contentShape(RoundedRectangle(cornerRadius: AjaniTheme.Radius.inner, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(task.detail.map { "\(task.title). \($0)" } ?? task.title)
        .accessibilityValue(task.isComplete ? "Done" : "Not done")
        .accessibilityHint(task.isComplete ? "Marks the task as not done" : "Marks the task as done")
        .accessibilityAddTraits(task.isComplete ? [.isButton, .isSelected] : .isButton)
    }
}

#Preview {
    NavigationStack {
        VisitDetailView(visitID: DemoFieldData.visits(on: .now)[3].id)
    }
    .environment(FieldOperationsStore())
}
