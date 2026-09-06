import Foundation
import Testing
@testable import AjaniFieldOperations

@Suite("Search and filtering")
struct VisitSearchTests {
    private let visits = [
        ShiftFixtures.visit(
            reference: "AV-2001",
            clientName: "Marguerite Okonjo",
            visitType: "Morning personal care",
            addressLine: "14 Bramble Court",
            district: "Selby Vale",
            postcode: "SV3 6QT",
            start: (7, 45),
            status: .completed
        ),
        ShiftFixtures.visit(
            reference: "AV-2002",
            clientName: "Priya Raman",
            visitType: "Post-discharge review",
            addressLine: "21 Halesmere Gardens",
            district: "Harbourne Fields",
            postcode: "SV17 9LP",
            start: (9, 40),
            status: .arrived
        ),
        ShiftFixtures.visit(
            reference: "AV-2003",
            clientName: "Ivor Bassey",
            visitType: "Wellbeing and mobility",
            addressLine: "Flat 12, Cedarcroft House",
            district: "Edgemoor",
            postcode: "SV15 3SN",
            start: (11, 0),
            status: .planned
        )
    ]

    @Test("An empty query returns the whole schedule in order")
    func emptyQueryReturnsEverything() {
        let results = VisitSearch.results(in: visits, searchText: "", statusFilter: .all)

        #expect(results.map(\.reference) == ["AV-2001", "AV-2002", "AV-2003"])
    }

    @Test("Whitespace-only queries are treated as empty")
    func whitespaceQueryReturnsEverything() {
        let results = VisitSearch.results(in: visits, searchText: "   ", statusFilter: .all)

        #expect(results.count == visits.count)
    }

    @Test("Search matches a client name regardless of case")
    func matchesClientNameCaseInsensitively() {
        let results = VisitSearch.results(in: visits, searchText: "priya", statusFilter: .all)

        #expect(results.map(\.reference) == ["AV-2002"])
    }

    @Test("Search matches a visit reference")
    func matchesReference() {
        let results = VisitSearch.results(in: visits, searchText: "AV-2003", statusFilter: .all)

        #expect(results.map(\.reference) == ["AV-2003"])
    }

    @Test("Search matches address, district and postcode")
    func matchesLocationFields() {
        #expect(VisitSearch.results(in: visits, searchText: "Bramble", statusFilter: .all).count == 1)
        #expect(VisitSearch.results(in: visits, searchText: "Edgemoor", statusFilter: .all).count == 1)
        #expect(VisitSearch.results(in: visits, searchText: "SV17", statusFilter: .all).count == 1)
    }

    @Test("Search ignores diacritics")
    func ignoresDiacritics() {
        let results = VisitSearch.results(in: visits, searchText: "Marguérite", statusFilter: .all)

        #expect(results.map(\.reference) == ["AV-2001"])
    }

    @Test("An unmatched query returns no visits")
    func unmatchedQueryReturnsNothing() {
        #expect(VisitSearch.results(in: visits, searchText: "zzzzz", statusFilter: .all).isEmpty)
    }

    @Test(
        "Status filters select the matching visits",
        arguments: [
            (VisitStatusFilter.all, ["AV-2001", "AV-2002", "AV-2003"]),
            (VisitStatusFilter.planned, ["AV-2003"]),
            (VisitStatusFilter.inProgress, ["AV-2002"]),
            (VisitStatusFilter.completed, ["AV-2001"])
        ]
    )
    func statusFilterSelectsMatchingVisits(filter: VisitStatusFilter, expected: [String]) {
        let results = VisitSearch.results(in: visits, searchText: "", statusFilter: filter)

        #expect(results.map(\.reference) == expected)
    }

    @Test("Search and status filter apply together")
    func combinesSearchAndStatusFilter() {
        #expect(VisitSearch.results(in: visits, searchText: "Priya", statusFilter: .planned).isEmpty)
        #expect(VisitSearch.results(in: visits, searchText: "Priya", statusFilter: .inProgress).count == 1)
    }

    @Test("In-progress covers both en route and arrived")
    func inProgressCoversTravellingAndOnSite() {
        #expect(VisitStatusFilter.inProgress.matches(.enRoute))
        #expect(VisitStatusFilter.inProgress.matches(.arrived))
        #expect(!VisitStatusFilter.inProgress.matches(.planned))
        #expect(!VisitStatusFilter.inProgress.matches(.completed))
    }
}
