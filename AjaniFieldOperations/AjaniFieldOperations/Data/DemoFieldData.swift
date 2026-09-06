import Foundation

/// Fixed records used to exercise the app before a backend exists.
/// Everything is anchored to a caller-supplied reference date so the schedule is
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

    static func visits(on referenceDate: Date, calendar: Calendar = .current) -> [Visit] {
        [
            Visit(
                id: identifier("22222222-0000-4000-A000-000000000001"),
                reference: "AV-1042",
                clientName: "Marguerite Okonjo",
                visitType: "Morning personal care",
                location: VisitLocation(
                    addressLine: "14 Bramble Court",
                    district: "Selby Vale",
                    postcode: "SV3 6QT",
                    travelMinutes: 0
                ),
                scheduledStart: time(7, 45, on: referenceDate, calendar: calendar),
                scheduledEnd: time(8, 30, on: referenceDate, calendar: calendar),
                priority: .standard,
                operationalNotes: [
                    "Key safe at the side gate; code held by the coordinator.",
                    "Prefers the kitchen door rather than the front entrance."
                ],
                tasks: [
                    VisitTask(id: identifier("33333333-0000-4000-A000-000000000001"), title: "Support with washing and dressing", isComplete: true),
                    VisitTask(id: identifier("33333333-0000-4000-A000-000000000002"), title: "Prepare breakfast and hot drink", isComplete: true),
                    VisitTask(id: identifier("33333333-0000-4000-A000-000000000003"), title: "Record fluid intake", detail: "Log before leaving the property", isComplete: true)
                ],
                status: .completed
            ),
            Visit(
                id: identifier("22222222-0000-4000-A000-000000000002"),
                reference: "AV-1043",
                clientName: "Desmond Achebe",
                visitType: "Medication support",
                location: VisitLocation(
                    addressLine: "8 Larkspur Row",
                    district: "Bournbrook Green",
                    postcode: "SV2 7BD",
                    travelMinutes: 10
                ),
                scheduledStart: time(8, 45, on: referenceDate, calendar: calendar),
                scheduledEnd: time(9, 15, on: referenceDate, calendar: calendar),
                priority: .standard,
                operationalNotes: [
                    "Blister pack is stored in the hallway cupboard.",
                    "Daughter usually attends the morning call."
                ],
                tasks: [
                    VisitTask(id: identifier("33333333-0000-4000-A000-000000000004"), title: "Prompt morning medication", isComplete: true),
                    VisitTask(id: identifier("33333333-0000-4000-A000-000000000005"), title: "Check blister pack for the week ahead", isComplete: true)
                ],
                status: .completed
            ),
            Visit(
                id: identifier("22222222-0000-4000-A000-000000000003"),
                reference: "AV-1044",
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
                    VisitTask(id: identifier("33333333-0000-4000-A000-000000000006"), title: "Review discharge notes with the client", isComplete: true),
                    VisitTask(id: identifier("33333333-0000-4000-A000-000000000007"), title: "Check wound dressing", detail: "Photograph not required"),
                    VisitTask(id: identifier("33333333-0000-4000-A000-000000000008"), title: "Confirm follow-up appointment is diarised")
                ],
                status: .arrived
            ),
            Visit(
                id: identifier("22222222-0000-4000-A000-000000000004"),
                reference: "AV-1045",
                clientName: "Ivor Bassey",
                visitType: "Wellbeing and mobility",
                location: VisitLocation(
                    addressLine: "Flat 12, Cedarcroft House",
                    district: "Edgemoor",
                    postcode: "SV15 3SN",
                    travelMinutes: 12
                ),
                scheduledStart: time(11, 0, on: referenceDate, calendar: calendar),
                scheduledEnd: time(11, 45, on: referenceDate, calendar: calendar),
                priority: .standard,
                operationalNotes: [
                    "Intercom is unreliable; call ahead on arrival.",
                    "Lift is out of service until the end of the month."
                ],
                tasks: [
                    VisitTask(id: identifier("33333333-0000-4000-A000-000000000009"), title: "Short mobility walk to the communal garden"),
                    VisitTask(id: identifier("33333333-0000-4000-A000-00000000000A"), title: "Check the kitchen for expired food"),
                    VisitTask(id: identifier("33333333-0000-4000-A000-00000000000B"), title: "Log mood and appetite")
                ],
                status: .planned
            ),
            Visit(
                id: identifier("22222222-0000-4000-A000-000000000005"),
                reference: "AV-1046",
                clientName: "Noor Hadid",
                visitType: "Lunchtime medication",
                location: VisitLocation(
                    addressLine: "47 Wren Meadow",
                    district: "Bearwood Rise",
                    postcode: "SV67 5RJ",
                    travelMinutes: 14
                ),
                scheduledStart: time(12, 15, on: referenceDate, calendar: calendar),
                scheduledEnd: time(12, 45, on: referenceDate, calendar: calendar),
                priority: .standard,
                operationalNotes: [
                    "Small dog in the hallway; keep the front door closed."
                ],
                tasks: [
                    VisitTask(id: identifier("33333333-0000-4000-A000-00000000000C"), title: "Prompt lunchtime medication"),
                    VisitTask(id: identifier("33333333-0000-4000-A000-00000000000D"), title: "Prepare a light lunch")
                ],
                status: .planned
            ),
            Visit(
                id: identifier("22222222-0000-4000-A000-000000000006"),
                reference: "AV-1047",
                clientName: "Beatrice Ferreira",
                visitType: "Complex care support",
                location: VisitLocation(
                    addressLine: "9 Tamarind Walk",
                    district: "Moseley Brook",
                    postcode: "SV13 8QN",
                    travelMinutes: 18
                ),
                scheduledStart: time(13, 30, on: referenceDate, calendar: calendar),
                scheduledEnd: time(14, 30, on: referenceDate, calendar: calendar),
                priority: .priority,
                operationalNotes: [
                    "Double-handed call; second practitioner joins from Round 6.",
                    "Hoist sling is stored in the airing cupboard."
                ],
                tasks: [
                    VisitTask(id: identifier("33333333-0000-4000-A000-00000000000E"), title: "Assisted transfer using the hoist"),
                    VisitTask(id: identifier("33333333-0000-4000-A000-00000000000F"), title: "Repositioning and skin check"),
                    VisitTask(id: identifier("33333333-0000-4000-A000-000000000010"), title: "Update the shared care record")
                ],
                status: .planned
            ),
            Visit(
                id: identifier("22222222-0000-4000-A000-000000000007"),
                reference: "AV-1048",
                clientName: "Callum Whitfield",
                visitType: "Evening preparation",
                location: VisitLocation(
                    addressLine: "62 Ashgrove Terrace",
                    district: "Kingsheath Park",
                    postcode: "SV14 6DP",
                    travelMinutes: 8
                ),
                scheduledStart: time(14, 45, on: referenceDate, calendar: calendar),
                scheduledEnd: time(15, 20, on: referenceDate, calendar: calendar),
                priority: .standard,
                operationalNotes: [
                    "Client is often in the back room; knock firmly."
                ],
                tasks: [
                    VisitTask(id: identifier("33333333-0000-4000-A000-000000000011"), title: "Prepare an evening meal"),
                    VisitTask(id: identifier("33333333-0000-4000-A000-000000000012"), title: "Set out night-time medication"),
                    VisitTask(id: identifier("33333333-0000-4000-A000-000000000013"), title: "Secure doors and windows")
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
