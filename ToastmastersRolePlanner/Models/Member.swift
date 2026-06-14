import Foundation
import SwiftData

/// A club member who can be assigned to meeting roles.
@Model
final class Member {
    var name: String = ""
    /// Active members are offered when assigning roles; inactive ones are kept
    /// for history but hidden from the assignment pickers.
    var isActive: Bool = true
    var notes: String = ""
    var dateAdded: Date = Date()

    init(name: String, isActive: Bool = true, notes: String = "") {
        self.name = name
        self.isActive = isActive
        self.notes = notes
        self.dateAdded = Date()
    }
}
