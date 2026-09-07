import SwiftUI

struct VisitsView: View {
    @Environment(FieldOperationsStore.self) private var store
    @State private var searchText = ""
    @State private var statusFilter: VisitStatusFilter = .all

    private var results: [Visit] {
        store.results(searchText: searchText, statusFilter: statusFilter)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                // The filter bar is a pinned section header rather than a top
                // safe-area inset: an inset there sits in the navigation bar's
                // large-title area and suppresses the title.
                LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                    Section {
                        LazyVStack(alignment: .leading, spacing: AjaniTheme.Spacing.m) {
                            if results.isEmpty {
                                EmptyStateView(
                                    symbolName: "magnifyingglass",
                                    title: "No matching visits",
                                    message: emptyStateMessage
                                )
                                .ajaniCard()
                                .accessibilityIdentifier(AccessibilityID.visitsEmptyState)
                            } else {
                                Text(resultSummary)
                                    .font(.footnote)
                                    .foregroundStyle(AjaniTheme.Palette.textSecondary)
                                    .padding(.horizontal, AjaniTheme.Spacing.xs)

                                ForEach(results) { visit in
                                    VisitRowView(visit: visit)
                                }
                            }
                        }
                        .padding(AjaniTheme.Spacing.l)
                    } header: {
                        filterBar
                    }
                }
            }
            .background(AjaniTheme.Palette.canvas)
            .scrollBounceBehavior(.basedOnSize)
            .scrollDismissesKeyboard(.immediately)
            .navigationTitle("Visits")
            .searchable(
                text: $searchText,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: "Search name, reference or address"
            )
            .navigationDestination(for: Visit.ID.self) { visitID in
                VisitDetailView(visitID: visitID)
            }
        }
    }

    private var filterBar: some View {
        VStack(spacing: 0) {
            Picker("Filter visits by status", selection: $statusFilter) {
                ForEach(VisitStatusFilter.allCases) { filter in
                    Text(filter.title).tag(filter)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, AjaniTheme.Spacing.l)
            .padding(.vertical, AjaniTheme.Spacing.s)

            Divider().overlay(AjaniTheme.Palette.separator)
        }
        .background(AjaniTheme.Palette.canvas)
    }

    private var resultSummary: String {
        let total = store.visits.count
        return results.count == total
            ? "Showing all \(total) visits"
            : "Showing \(results.count) of \(total) visits"
    }

    private var emptyStateMessage: String {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if query.isEmpty {
            return statusFilter == .all
                ? "There are no visits in this shift."
                : "No visits are currently \(statusFilter.title.lowercased())."
        }
        return "Nothing matches “\(query)” in this filter."
    }
}

#Preview {
    VisitsView()
        .environment(FieldOperationsStore())
}
