import Foundation
import Testing
@testable import AjaniFieldOperations

/// The native round and the browser round are one demonstration, so the people,
/// references, times and checklists have to agree.
@Suite("The demonstration round")
@MainActor
struct DemoRoundTests {
    private var visits: [Visit] {
        DemoFieldData.visits(on: ShiftFixtures.referenceDate, calendar: ShiftFixtures.calendar)
    }

    @Test("Opens on seven visits: two completed, one arrived, four planned")
    func opensOnTheExpectedShape() {
        let statuses = ShiftPlanner.chronological(visits).map(\.status)

        #expect(statuses == [.completed, .completed, .arrived, .planned, .planned, .planned, .planned])
    }

    @Test("Carries the agreed references and people, in schedule order")
    func carriesTheAgreedPeople() {
        let ordered = ShiftPlanner.chronological(visits)

        #expect(ordered.map(\.reference) == [
            "AV-1041", "AV-1042", "AV-1043", "AV-1044", "AV-1045", "AV-1046", "AV-1047"
        ])
        #expect(ordered.map(\.clientName) == [
            "Marguerite Okonjo",
            "Desmond Achebe",
            "Priya Raman",
            "Ivor Bankole",
            "Halina Nowak",
            "Terrence Boakye",
            "Sunita Kaur"
        ])
    }

    @Test("Schedules each visit at the agreed time")
    func schedulesTheAgreedTimes() {
        let calendar = ShiftFixtures.calendar
        let windows = ShiftPlanner.chronological(visits).map { visit in
            let start = calendar.dateComponents([.hour, .minute], from: visit.scheduledStart)
            let end = calendar.dateComponents([.hour, .minute], from: visit.scheduledEnd)
            return "\(start.hour ?? 0):\(String(format: "%02d", start.minute ?? 0))-\(end.hour ?? 0):\(String(format: "%02d", end.minute ?? 0))"
        }

        #expect(windows == [
            "7:45-8:30",
            "8:45-9:15",
            "9:40-10:40",
            "11:00-11:45",
            "12:15-12:50",
            "13:30-14:10",
            "14:30-15:15"
        ])
    }

    @Test("Gives every visit three tasks, with Priya's review part-done")
    func carriesTheAgreedChecklists() throws {
        #expect(visits.allSatisfy { $0.tasks.count == 3 })

        let priya = try #require(visits.first { $0.reference == "AV-1043" })
        #expect(priya.completedTaskCount == 1)
        #expect(priya.outstandingTaskCount == 2)
        #expect(priya.tasks[0].title == "Review discharge notes with the client")
        #expect(priya.tasks[1].detail == "Photograph not required")
        #expect(priya.priority == .priority)
    }

    @Test("Marks only the post-discharge review as priority")
    func marksOnlyOneVisitPriority() {
        #expect(visits.filter { $0.priority == .priority }.map(\.reference) == ["AV-1043"])
    }

    @Test("Carries an operational note on every visit")
    func carriesOperationalNotes() throws {
        #expect(visits.allSatisfy { !$0.operationalNotes.isEmpty })

        let marguerite = try #require(visits.first { $0.reference == "AV-1041" })
        #expect(marguerite.operationalNotes == ["Prefers the back door; the front gate sticks after rain."])

        let priya = try #require(visits.first { $0.reference == "AV-1043" })
        #expect(priya.operationalNotes.count == 2)
    }

    @Test("Starts with exactly one active visit, and it is the visit in hand")
    func startsWithOneActiveVisit() throws {
        let store = ShiftFixtures.demoStore()

        let active = try #require(store.activeVisit)
        #expect(active.reference == "AV-1043")
        #expect(store.upNextVisit?.id == active.id)
        #expect(store.visits.filter { $0.status.isInProgress }.count == 1)
    }

    @Test("Falls back to the earliest planned visit once the active one closes")
    func fallsBackToEarliestPlanned() throws {
        let store = ShiftFixtures.demoStore()
        let active = try #require(store.activeVisit)

        #expect(store.advanceStatus(of: active.id, confirmed: true))

        #expect(store.activeVisit == nil)
        #expect(store.upNextVisit?.reference == "AV-1044")
    }

    @Test("Runs the shift from 7:30 to 15:45 on the reference day")
    func runsTheAgreedShift() {
        let calendar = ShiftFixtures.calendar
        let shift = DemoFieldData.shift(on: ShiftFixtures.referenceDate, calendar: calendar)

        #expect(calendar.component(.hour, from: shift.start) == 7)
        #expect(calendar.component(.minute, from: shift.start) == 30)
        #expect(calendar.component(.hour, from: shift.end) == 15)
        #expect(calendar.component(.minute, from: shift.end) == 45)
        #expect(shift.region == "Southside · Round 4")
    }
}
