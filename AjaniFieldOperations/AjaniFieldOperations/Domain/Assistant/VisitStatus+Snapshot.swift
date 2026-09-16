import Foundation

extension VisitStatus {
    /// The status as the assistant endpoint's contract spells it.
    ///
    /// The server and the browser client share these strings, so they are stated
    /// here rather than derived from the Swift case names, which differ.
    nonisolated var snapshotValue: String {
        switch self {
        case .planned: "planned"
        case .enRoute: "en-route"
        case .arrived: "arrived"
        case .completed: "completed"
        case .cancelled: "cancelled"
        }
    }
}
