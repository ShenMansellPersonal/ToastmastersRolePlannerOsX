import Foundation
import SwiftData

/// A specific meeting on a given date. Its agenda is snapshotted from a
/// template at creation time (into `RoleAssignment`s) so that later edits to
/// the template don't rewrite past meetings.
@Model
final class Meeting {
    var date: Date = Date()
    var theme: String = ""
    /// Name of the template this meeting was created from (for display/history).
    var templateName: String = ""

    @Relationship(deleteRule: .cascade, inverse: \RoleAssignment.meeting)
    var assignments: [RoleAssignment] = []

    /// Members explicitly marked as absent for this meeting.
    @Relationship
    var absentees: [Member] = []

    init(date: Date = Date(), theme: String = "", templateName: String = "") {
        self.date = date
        self.theme = theme
        self.templateName = templateName
    }

    /// Assignments in agenda order.
    var orderedAssignments: [RoleAssignment] {
        assignments.sorted { $0.order < $1.order }
    }

    /// Builds the assignment list from a template's slots.
    func applyTemplate(_ template: MeetingTemplate) {
        templateName = template.name
        assignments = template.orderedSlots.map { slot in
            RoleAssignment(role: slot.role, order: slot.order, instanceNumber: slot.instanceNumber)
        }
    }
}

/// A single role position within a meeting, optionally filled by a member.
@Model
final class RoleAssignment {
    var roleRaw: String = RoleType.toastmaster.rawValue
    var order: Int = 0
    var instanceNumber: Int = 0

    @Relationship
    var member: Member?

    var meeting: Meeting?

    /// Per-meeting timing override. When all three are set, they take precedence
    /// over the role's default times; otherwise the role default is used.
    var overrideGreen: Int?
    var overrideYellow: Int?
    var overrideRed: Int?

    init(role: RoleType, order: Int, instanceNumber: Int = 0, member: Member? = nil) {
        self.roleRaw = role.rawValue
        self.order = order
        self.instanceNumber = instanceNumber
        self.member = member
    }

    var role: RoleType {
        RoleType(rawValue: roleRaw) ?? .toastmaster
    }

    var label: String {
        role.label(instance: instanceNumber)
    }

    /// True when this meeting overrides the default timing for the role.
    var hasTimingOverride: Bool {
        overrideGreen != nil && overrideYellow != nil && overrideRed != nil
    }

    /// The override times, if a full override is set.
    var overrideTiming: Timing? {
        guard let green = overrideGreen, let yellow = overrideYellow, let red = overrideRed else {
            return nil
        }
        return Timing(green: green, yellow: yellow, red: red)
    }

    /// Sets (or clears, with `nil`) the timing override.
    func setOverride(_ timing: Timing?) {
        overrideGreen = timing?.green
        overrideYellow = timing?.yellow
        overrideRed = timing?.red
    }
}
