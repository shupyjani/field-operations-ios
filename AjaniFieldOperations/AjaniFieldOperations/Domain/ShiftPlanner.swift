import Foundation

nonisolated struct ShiftProgress: Hashable, Sendable {
    let completed: Int
    let total: Int

    var remaining: Int {
        max(total - completed, 0)
    }

    var fraction: Double {
        guard total > 0 else { return 0 }
        return Double(completed) / Double(total)
    }

    var percentage: Int {
        Int((fraction * 100).rounded())
    }
}

/// Pure scheduling rules. No clock, no storage, no SwiftUI.
nonisolated enum ShiftPlanner {
    /// Visits in the order the worker will travel them.
    static func chronological(_ visits: [Visit]) -> [Visit] {
        visits.sorted { lhs, rhs in
            if lhs.scheduledStart != rhs.scheduledStart {
                return lhs.scheduledStart < rhs.scheduledStart
            }
            return lhs.reference < rhs.reference
        }
    }

    static func progress(for visits: [Visit]) -> ShiftProgress {
        ShiftProgress(
            completed: visits.count { $0.status == .completed },
            total: visits.count
        )
    }

    /// The visit needing the worker's attention: one already under way, otherwise the
    /// earliest visit still to be started.
    static func upNext(in visits: [Visit]) -> Visit? {
        let ordered = chronological(visits)
        return ordered.first { $0.status.isInProgress } ?? ordered.first { $0.status == .planned }
    }
}
