import Foundation

/// How much of the round is behind the practitioner.
///
/// Completed and cancelled are counted separately and never merged. A cancelled
/// visit is resolved, in that nothing more will happen at that address, but it
/// was not completed and must never inflate the completed count. The bar tracks
/// *resolved* — the visits no longer waiting — because that is what "how much is
/// left" means on a doorstep.
nonisolated struct ShiftProgress: Hashable, Sendable {
    let completed: Int
    let cancelled: Int
    let total: Int

    init(completed: Int, cancelled: Int = 0, total: Int) {
        self.completed = completed
        self.cancelled = cancelled
        self.total = total
    }

    var resolved: Int {
        completed + cancelled
    }

    var remaining: Int {
        max(total - resolved, 0)
    }

    var fraction: Double {
        guard total > 0 else { return 0 }
        return Double(resolved) / Double(total)
    }

    var percentage: Int {
        Int((fraction * 100).rounded())
    }

    /// The progress sentence, as the phrases it is made of.
    ///
    /// Two shapes, because a round with no cancellations should read exactly as it
    /// always has. The longer form appears only once there is a cancellation to
    /// account for, and then keeps completed and cancelled visibly apart.
    var phrases: [String] {
        guard cancelled > 0 else {
            return ["\(completed) of \(total) visits complete", "\(remaining) remaining"]
        }

        return [
            "\(resolved) of \(total) visits resolved",
            "\(completed) completed",
            "\(cancelled) cancelled",
            "\(remaining) remaining"
        ]
    }

    /// The same sentence as one string, so the spoken form and the laid-out one
    /// cannot drift apart.
    var summary: String {
        phrases.joined(separator: " · ")
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
            cancelled: visits.count { $0.status == .cancelled },
            total: visits.count
        )
    }

    /// The visit needing the worker's attention: one already under way, otherwise the
    /// earliest visit still to be started.
    ///
    /// Cancelled visits are passed over the same way completed ones are — nothing
    /// further happens at that address — so neither can ever be the visit in hand.
    static func upNext(in visits: [Visit]) -> Visit? {
        let ordered = chronological(visits)
        return ordered.first { $0.status.isInProgress } ?? ordered.first { $0.status == .planned }
    }

    /// The visit the practitioner is currently on, if any.
    ///
    /// "Active" is en route or arrived: the two statuses that place one person at
    /// one address. Exactly one visit may hold it.
    static func activeVisit(in visits: [Visit]) -> Visit? {
        chronological(visits).first { $0.status.isInProgress }
    }
}
