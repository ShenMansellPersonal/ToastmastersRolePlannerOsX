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
            RoleAssignment(
                roleKey: slot.roleRaw,
                order: slot.order,
                instanceNumber: slot.instanceNumber,
                customLabel: slot.customLabel
            )
        }
    }
}

/// A single role position within a meeting, optionally filled by a member.
@Model
final class RoleAssignment {
    /// Stable key of the `Role` this assignment fills (see `Role.key`).
    var roleRaw: String = ""
    var order: Int = 0
    var instanceNumber: Int = 0
    /// Optional override for the displayed agenda line (copied from the
    /// template slot). When empty, the label is derived from the role.
    var customLabel: String = ""

    @Relationship
    var member: Member?

    var meeting: Meeting?

    /// Per-meeting timing override. When all three are set, they take precedence
    /// over the role's default times; otherwise the role default is used.
    var overrideGreen: Int?
    var overrideYellow: Int?
    var overrideRed: Int?

    init(roleKey: String, order: Int, instanceNumber: Int = 0, customLabel: String = "", member: Member? = nil) {
        self.roleRaw = roleKey
        self.order = order
        self.instanceNumber = instanceNumber
        self.customLabel = customLabel
        self.member = member
    }

    /// The label to display, given the resolved `Role` (nil if it was deleted).
    func displayLabel(_ role: Role?) -> String {
        if !customLabel.isEmpty { return customLabel }
        return role?.label(instance: instanceNumber) ?? "(deleted role)"
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
