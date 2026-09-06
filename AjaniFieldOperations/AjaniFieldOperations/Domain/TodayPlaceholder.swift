import Foundation

/// Why the Today screen has nothing to show in one of its slots.
///
/// The reasons are distinct on purpose: a shift with no visits at all must not be
/// described as finished, nor as hidden by a preference the worker did not set.
nonisolated enum TodayPlaceholder: Hashable, Sendable {
    /// The shift contains no visits whatsoever.
    case shiftEmpty
    /// Every visit in the shift has been completed.
    case allComplete
    /// Visits remain, but the completed-visit preference hides all of them.
    case completedHidden
}
