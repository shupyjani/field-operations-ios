import Foundation

/// The demonstration round.
///
/// Every person, address, postcode and reference here is invented. The shift is
/// Naomi Adeyemi's Southside round of seven visits — two already complete and one
/// in hand — which is the same round the browser recreation opens on.
///
/// Times are anchored to a caller-supplied reference date so the schedule is
/// deterministic and independent of the wall clock.
nonisolated enum DemoFieldData {
    static let worker = Worker(
        id: identifier("11111111-0000-4000-A000-000000000001"),
        firstName: "Naomi",
        lastName: "Adeyemi",
        role: "Community support practitioner",
        team: "Southside field team",
        staffReference: "FT-2291"
    )

    static func shift(on referenceDate: Date, calendar: Calendar = .current) -> Shift {
        Shift(
            date: calendar.startOfDay(for: referenceDate),
            start: time(7, 30, on: referenceDate, calendar: calendar),
            end: time(15, 45, on: referenceDate, calendar: calendar),
            region: "Southside · Round 4"
        )
    }

    /// Seven visits in chronological order: two completed, one arrived, four
    /// planned. That is the 2 of 7 the shift summary opens on.
    /// References are "AV" — Ajani Visit — plus a stable sequential number.
    static func visits(on referenceDate: Date, calendar: Calendar = .current) -> [Visit] {
        [
            Visit(
                id: identifier("22222222-0000-4000-A000-000000000001"),
                reference: "AV-1041",
                clientName: "Marguerite Okonjo",
                visitType: "Morning personal care",
                location: VisitLocation(
                    addressLine: "14 Bramble Court",
                    district: "Selby Vale",
                    postcode: "SV3 6QT",
                    travelMinutes: 10
                ),
                scheduledStart: time(7, 45, on: referenceDate, calendar: calendar),
                scheduledEnd: time(8, 30, on: referenceDate, calendar: calendar),
                priority: .standard,
                operationalNotes: ["Prefers the back door; the front gate sticks after rain."],
                tasks: [
                    VisitTask(id: identifier("33333333-0000-4000-A000-000000000001"), title: "Support with washing and dressing", isComplete: true),
                    VisitTask(id: identifier("33333333-0000-4000-A000-000000000002"), title: "Prepare breakfast and a hot drink", isComplete: true),
                    VisitTask(id: identifier("33333333-0000-4000-A000-000000000003"), title: "Record fluid intake", isComplete: true)
                ],
                status: .completed
            ),
            Visit(
                id: identifier("22222222-0000-4000-A000-000000000002"),
                reference: "AV-1042",
                clientName: "Desmond Achebe",
                visitType: "Medication support",
                location: VisitLocation(
                    addressLine: "8 Larkspur Row",
                    district: "Bournbrook Green",
                    postcode: "SV2 7BD",
                    travelMinutes: 12
                ),
                scheduledStart: time(8, 45, on: referenceDate, calendar: calendar),
                scheduledEnd: time(9, 15, on: referenceDate, calendar: calendar),
                priority: .standard,
                operationalNotes: ["Daughter usually calls around nine; happy to be interrupted."],
                tasks: [
                    VisitTask(id: identifier("33333333-0000-4000-A000-000000000004"), title: "Check the blister pack against the chart", isComplete: true),
                    VisitTask(id: identifier("33333333-0000-4000-A000-000000000005"), title: "Prompt morning medication", isComplete: true),
                    VisitTask(id: identifier("33333333-0000-4000-A000-000000000006"), title: "Note any missed doses", isComplete: true)
                ],
                status: .completed
            ),
            Visit(
                id: identifier("22222222-0000-4000-A000-000000000003"),
                reference: "AV-1043",
                clientName: "Priya Raman",
                visitType: "Post-discharge review",
                location: VisitLocation(
                    addressLine: "21 Halesmere Gardens",
                    district: "Harbourne Fields",
                    postcode: "SV17 9LP",
                    travelMinutes: 15
                ),
                scheduledStart: time(9, 40, on: referenceDate, calendar: calendar),
                scheduledEnd: time(10, 40, on: referenceDate, calendar: calendar),
                priority: .priority,
                operationalNotes: [
                    "First visit since discharge; escalate any new pain to the duty line.",
                    "Mobility frame is kept beside the stairs."
                ],
                tasks: [
                    VisitTask(id: identifier("33333333-0000-4000-A000-000000000007"), title: "Review discharge notes with the client", isComplete: true),
                    VisitTask(id: identifier("33333333-0000-4000-A000-000000000008"), title: "Check wound dressing", detail: "Photograph not required"),
                    VisitTask(id: identifier("33333333-0000-4000-A000-000000000009"), title: "Confirm follow-up appointment is diarised")
                ],
                status: .arrived
            ),
            Visit(
                id: identifier("22222222-0000-4000-A000-000000000004"),
                reference: "AV-1044",
                clientName: "Ivor Bankole",
                visitType: "Wellbeing and mobility",
                location: VisitLocation(
                    addressLine: "3 Pennycress Walk",
                    district: "Selby Vale",
                    postcode: "SV3 8HD",
                    travelMinutes: 14
                ),
                scheduledStart: time(11, 0, on: referenceDate, calendar: calendar),
                scheduledEnd: time(11, 45, on: referenceDate, calendar: calendar),
                priority: .standard,
                operationalNotes: ["Prefers to do the circuit before any paperwork."],
                tasks: [
                    VisitTask(id: identifier("33333333-0000-4000-A000-00000000000A"), title: "Walk the hallway circuit twice"),
                    VisitTask(id: identifier("33333333-0000-4000-A000-00000000000B"), title: "Check the stair rail is secure"),
                    VisitTask(id: identifier("33333333-0000-4000-A000-00000000000C"), title: "Log how the exercises were tolerated")
                ],
                status: .planned
            ),
            Visit(
                id: identifier("22222222-0000-4000-A000-000000000005"),
                reference: "AV-1045",
                clientName: "Halina Nowak",
                visitType: "Medication support",
                location: VisitLocation(
                    addressLine: "46 Ashcombe Rise",
                    district: "Bournbrook Green",
                    postcode: "SV2 4RN",
                    travelMinutes: 9
                ),
                scheduledStart: time(12, 15, on: referenceDate, calendar: calendar),
                scheduledEnd: time(12, 50, on: referenceDate, calendar: calendar),
                priority: .standard,
                operationalNotes: ["Hard of hearing on the left side."],
                tasks: [
                    VisitTask(id: identifier("33333333-0000-4000-A000-00000000000D"), title: "Prompt midday medication"),
                    VisitTask(id: identifier("33333333-0000-4000-A000-00000000000E"), title: "Refill the water jug"),
                    VisitTask(id: identifier("33333333-0000-4000-A000-00000000000F"), title: "Check the repeat prescription date")
                ],
                status: .planned
            ),
            Visit(
                id: identifier("22222222-0000-4000-A000-000000000006"),
                reference: "AV-1046",
                clientName: "Terrence Boakye",
                visitType: "Afternoon personal care",
                location: VisitLocation(
                    addressLine: "9 Miller's Yard",
                    district: "Harbourne Fields",
                    postcode: "SV17 2PJ",
                    travelMinutes: 16
                ),
                scheduledStart: time(13, 30, on: referenceDate, calendar: calendar),
                scheduledEnd: time(14, 10, on: referenceDate, calendar: calendar),
                priority: .standard,
                operationalNotes: ["Key safe is to the right of the porch."],
                tasks: [
                    VisitTask(id: identifier("33333333-0000-4000-A000-000000000010"), title: "Support with a change of clothes"),
                    VisitTask(id: identifier("33333333-0000-4000-A000-000000000011"), title: "Prepare a light meal"),
                    VisitTask(id: identifier("33333333-0000-4000-A000-000000000012"), title: "Empty and reline the kitchen bin")
                ],
                status: .planned
            ),
            Visit(
                id: identifier("22222222-0000-4000-A000-000000000007"),
                reference: "AV-1047",
                clientName: "Sunita Kaur",
                visitType: "Wellbeing and mobility",
                location: VisitLocation(
                    addressLine: "27 Thornleigh Avenue",
                    district: "Selby Vale",
                    postcode: "SV3 5QW",
                    travelMinutes: 11
                ),
                scheduledStart: time(14, 30, on: referenceDate, calendar: calendar),
                scheduledEnd: time(15, 15, on: referenceDate, calendar: calendar),
                priority: .standard,
                operationalNotes: ["Cat tends to slip out; keep the inner door closed."],
                tasks: [
                    VisitTask(id: identifier("33333333-0000-4000-A000-000000000013"), title: "Seated exercises, ten minutes"),
                    VisitTask(id: identifier("33333333-0000-4000-A000-000000000014"), title: "Check the pendant alarm is charged"),
                    VisitTask(id: identifier("33333333-0000-4000-A000-000000000015"), title: "Confirm next week's visit times")
                ],
                status: .planned
            )
        ]
    }

    private static func time(_ hour: Int, _ minute: Int, on date: Date, calendar: Calendar) -> Date {
        // Searching forward from midnight keeps every visit on the reference day,
        // whatever time of day the caller passes in.
        let startOfDay = calendar.startOfDay(for: date)
        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: startOfDay) ?? startOfDay
    }

    private static func identifier(_ value: String) -> UUID {
        UUID(uuidString: value) ?? UUID()
    }
}
