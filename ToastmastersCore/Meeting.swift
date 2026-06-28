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

    /// Members explicitly marked as absent for this meeting. Many-to-many (a
    /// member can be absent from many meetings) via the inverse on `Member`.
    @Relationship(inverse: \Member.absentMeetings)
    var absentees: [Member] = []

    /// Members who spoke during Table Topics at this meeting. Tracked as a simple
    /// ticklist (independent of roles). Many-to-many via the inverse on `Member`.
    @Relationship(inverse: \Member.tableTopicsMeetings)
    var tableTopicsSpeakers: [Member] = []

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

    /// The assigned current member, if any.
    @Relationship
    var member: Member?
    /// The assignee's name as text. Mirrors `member.name` when linked, but is
    /// also kept for people who aren't (or are no longer) in the member list —
    /// so historic data survives. Empty means unassigned.
    var memberName: String = ""

    var meeting: Meeting?

    /// Per-meeting timing override. When all three are set, they take precedence
    /// over the role's default times; otherwise the role default is used.
    var overrideGreen: Int?
    var overrideYellow: Int?
    var overrideRed: Int?

    init(roleKey: String, order: Int, instanceNumber: Int = 0, customLabel: String = "", member: Member? = nil, memberName: String = "") {
        self.roleRaw = roleKey
        self.order = order
        self.instanceNumber = instanceNumber
        self.customLabel = customLabel
        self.member = member
        self.memberName = member?.name ?? memberName
    }

    /// The display name of whoever holds this role: the linked member's name,
    /// else the stored text name, else nil (unassigned).
    var assigneeName: String? {
        if let member { return member.name }
        return memberName.isEmpty ? nil : memberName
    }

    /// True when someone (linked or text-only) is assigned.
    var isFilled: Bool { assigneeName != nil }

    /// True when a name is recorded but it isn't a current member.
    var isUnlinkedName: Bool { member == nil && !memberName.isEmpty }

    /// Assigns a current member (keeping the text name in sync), or clears
    /// the assignment entirely when passed nil.
    func assign(_ newMember: Member?) {
        member = newMember
        memberName = newMember?.name ?? ""
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
