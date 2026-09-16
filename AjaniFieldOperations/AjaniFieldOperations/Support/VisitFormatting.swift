import Foundation

nonisolated enum VisitFormatting {
    static func time(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }

    static func window(from start: Date, to end: Date) -> String {
        "\(time(start))–\(time(end))"
    }

    /// Spoken form of a time window, so VoiceOver does not read the dash as punctuation.
    static func spokenWindow(from start: Date, to end: Date) -> String {
        "\(time(start)) to \(time(end))"
    }

    static func duration(minutes: Int) -> String {
        let hours = minutes / 60
        let remainder = minutes % 60
        switch (hours, remainder) {
        case (0, let m): return "\(m) min"
        case (let h, 0): return h == 1 ? "1 hr" : "\(h) hr"
        case (let h, let m): return "\(h) hr \(m) min"
        }
    }

    static func fullDate(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.wide).day().month(.wide))
    }
}
