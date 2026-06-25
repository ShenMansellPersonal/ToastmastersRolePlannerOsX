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
    /// When the record was created in the app.
    var dateAdded: Date = Date()
    /// When the member joined the club. Defaults to 1 Jan 2025 for records that
    /// predate this field (and for imports without a joined date).
    var joinedDate: Date = Member.defaultJoinedDate

    /// Inverse of `Meeting.absentees` — makes the absentee link many-to-many so
    /// a member can be marked absent from any number of meetings independently.
    var absentMeetings: [Meeting] = []

    init(name: String, isActive: Bool = true, notes: String = "", joinedDate: Date = Date()) {
        self.name = name
        self.isActive = isActive
        self.notes = notes
        self.dateAdded = Date()
        self.joinedDate = joinedDate
    }

    /// 2025-01-01 (UTC midnight) — the fallback joined date.
    static let defaultJoinedDate = Date(timeIntervalSince1970: 1_735_689_600)
}
