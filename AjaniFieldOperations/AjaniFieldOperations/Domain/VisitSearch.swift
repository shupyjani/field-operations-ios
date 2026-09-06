import Foundation

/// Search and status filtering for the Visits screen.
nonisolated enum VisitSearch {
    static func results(
        in visits: [Visit],
        searchText: String,
        statusFilter: VisitStatusFilter
    ) -> [Visit] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return ShiftPlanner.chronological(visits)
            .filter { statusFilter.matches($0.status) }
            .filter { query.isEmpty || matches($0, query: query) }
    }

    private static func matches(_ visit: Visit, query: String) -> Bool {
        let haystack = [
            visit.clientName,
            visit.reference,
            visit.visitType,
            visit.location.addressLine,
            visit.location.district,
            visit.location.postcode
        ]
        return haystack.contains { field in
            field.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil
        }
    }
}
