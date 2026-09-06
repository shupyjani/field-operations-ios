import Foundation

nonisolated struct Worker: Identifiable, Hashable, Sendable {
    let id: UUID
    let firstName: String
    let lastName: String
    let role: String
    let team: String
    let staffReference: String

    var fullName: String {
        "\(firstName) \(lastName)"
    }

    var initials: String {
        "\(firstName.prefix(1))\(lastName.prefix(1))"
    }
}

nonisolated struct Shift: Hashable, Sendable {
    let date: Date
    let start: Date
    let end: Date
    let region: String
}
