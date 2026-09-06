import Foundation
@testable import AjaniFieldOperations

/// Deterministic building blocks for the unit tests. Every date is derived from a
/// fixed reference point in a fixed calendar, so no test reads the wall clock.
enum ShiftFixtures {
    static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        return calendar
    }

    /// Thursday 5 March 2026, 09:30 GMT.
    static let referenceDate = calendar.date(
        from: DateComponents(year: 2026, month: 3, day: 5, hour: 9, minute: 30)
    ) ?? Date(timeIntervalSince1970: 0)

    static func time(_ hour: Int, _ minute: Int) -> Date {
        calendar.date(
            bySettingHour: hour,
            minute: minute,
            second: 0,
            of: calendar.startOfDay(for: referenceDate)
        ) ?? referenceDate
    }

    static func visit(
        reference: String,
        clientName: String = "Test Client",
        visitType: String = "Wellbeing check",
        addressLine: String = "1 Test Row",
        district: String = "Testfield",
        postcode: String = "TS1 1AA",
        start: (hour: Int, minute: Int),
        durationMinutes: Int = 30,
        status: VisitStatus = .planned,
        tasks: [VisitTask] = []
    ) -> Visit {
        let startDate = time(start.hour, start.minute)
        return Visit(
            id: UUID(),
            reference: reference,
            clientName: clientName,
            visitType: visitType,
            location: VisitLocation(
                addressLine: addressLine,
                district: district,
                postcode: postcode,
                travelMinutes: 10
            ),
            scheduledStart: startDate,
            scheduledEnd: startDate.addingTimeInterval(TimeInterval(durationMinutes * 60)),
            priority: .standard,
            operationalNotes: ["Test note"],
            tasks: tasks,
            status: status
        )
    }

    static func task(_ title: String, isComplete: Bool = false) -> VisitTask {
        VisitTask(id: UUID(), title: title, isComplete: isComplete)
    }

    @MainActor
    static func store(visits: [Visit]) -> FieldOperationsStore {
        FieldOperationsStore(
            worker: DemoFieldData.worker,
            shift: DemoFieldData.shift(on: referenceDate, calendar: calendar),
            visits: visits,
            referenceDate: referenceDate,
            calendar: calendar
        )
    }

    @MainActor
    static func demoStore() -> FieldOperationsStore {
        FieldOperationsStore(referenceDate: referenceDate, calendar: calendar)
    }
}
