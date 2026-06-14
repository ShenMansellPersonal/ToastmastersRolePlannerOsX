import Foundation
import SwiftData

/// A reusable agenda: an ordered list of role slots that defines which roles a
/// meeting following this template will need filled.
@Model
final class MeetingTemplate {
    var name: String = ""
    var details: String = ""
    var dateCreated: Date = Date()

    @Relationship(deleteRule: .cascade, inverse: \TemplateSlot.template)
    var slots: [TemplateSlot] = []

    init(name: String, details: String = "") {
        self.name = name
        self.details = details
        self.dateCreated = Date()
    }

    /// Slots in agenda order.
    var orderedSlots: [TemplateSlot] {
        slots.sorted { $0.order < $1.order }
    }
}

/// One role position within a template's agenda.
@Model
final class TemplateSlot {
    /// Raw value of the `RoleType`.
    var roleRaw: String = RoleType.toastmaster.rawValue
    /// Position in the agenda (ascending).
    var order: Int = 0
    /// Groups repeating roles (e.g. Speaker #2 and its intro/evaluation share
    /// the same instance number). 0 for non-repeating roles.
    var instanceNumber: Int = 0

    var template: MeetingTemplate?

    init(role: RoleType, order: Int, instanceNumber: Int = 0) {
        self.roleRaw = role.rawValue
        self.order = order
        self.instanceNumber = instanceNumber
    }

    var role: RoleType {
        RoleType(rawValue: roleRaw) ?? .toastmaster
    }

    var label: String {
        role.label(instance: instanceNumber)
    }
}
