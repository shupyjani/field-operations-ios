import SwiftUI

struct TodayView: View {
    @Environment(FieldOperationsStore.self) private var store

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AjaniTheme.Spacing.l) {
                    ShiftSummaryCard(
                        greeting: store.greeting,
                        worker: store.worker,
                        shift: store.shift,
                        progress: store.progress
                    )

                    if let upNext = store.upNextVisit {
                        UpNextCard(visit: upNext)
                    } else if let placeholder = store.upNextPlaceholder {
                        placeholder.emptyState.ajaniCard()
                    }

                    scheduleSection
                }
                .padding(AjaniTheme.Spacing.l)
            }
            .background(AjaniTheme.Palette.canvas)
            .scrollBounceBehavior(.basedOnSize)
            .accessibilityIdentifier(AccessibilityID.todayScreen)
            .navigationTitle("Today")
            .navigationDestination(for: Visit.ID.self) { visitID in
                VisitDetailView(visitID: visitID)
            }
        }
    }

    private var scheduleSection: some View {
        VStack(alignment: .leading, spacing: AjaniTheme.Spacing.m) {
            SectionHeader(title: "Schedule", subtitle: scheduleSubtitle)

            if let placeholder = store.schedulePlaceholder {
                placeholder.emptyState.ajaniCard()
            } else {
                LazyVStack(spacing: AjaniTheme.Spacing.m) {
                    ForEach(store.todaySchedule) { visit in
                        VisitRowView(visit: visit)
                    }
                }
            }
        }
    }

    private var scheduleSubtitle: String {
        let progress = store.progress
        let visitCount = progress.total == 1 ? "1 visit" : "\(progress.total) visits"
        return "\(visitCount) · \(progress.remaining) remaining"
    }
}

private extension TodayPlaceholder {
    var emptyState: EmptyStateView {
        switch self {
        case .shiftEmpty:
            EmptyStateView(
                symbolName: "calendar",
                title: "No visits scheduled",
                message: "This shift has no visits assigned to it."
            )
        case .allComplete:
            EmptyStateView(
                symbolName: "checkmark.seal",
                title: "Every visit is complete",
                message: "Nothing further is scheduled for this shift."
            )
        case .completedHidden:
            EmptyStateView(
                symbolName: "eye.slash",
                title: "No visits to show",
                message: "Completed visits are hidden by your preferences."
            )
        }
    }
}

#Preview {
    TodayView()
        .environment(FieldOperationsStore())
}
