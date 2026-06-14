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

extension MeetingTemplate {
    static let defaultTemplateName = "3 speeches (default)"

    /// Creates the built-in starter template once (tracked via UserDefaults so a
    /// deliberate deletion isn't undone on the next launch).
    static func ensureDefaultSeeded(in context: ModelContext) {
        let seededKey = "didSeedDefaultTemplate"
        guard !UserDefaults.standard.bool(forKey: seededKey) else { return }

        let template = MeetingTemplate(name: defaultTemplateName, details: "Built-in starter agenda.")
        context.insert(template)

        var order = 0
        func add(_ role: RoleType, instance: Int = 0, label: String = "") {
            template.slots.append(
                TemplateSlot(role: role, order: order, instanceNumber: instance, customLabel: label)
            )
            order += 1
        }

        add(.sergeantAtArms)
        add(.toastmaster)
        add(.grammarian)
        add(.warmUp)
        for speaker in 1...3 {
            add(.speakerIntroduction, instance: speaker)
            add(.speaker, instance: speaker)
        }
        add(.tableTopicsMaster)
        add(.breakTime)
        add(.sergeantAtArms, label: "Sergeant at Arms (welcome back)")
        add(.toastmaster)
        for speaker in 1...3 {
            add(.speakerEvaluation, instance: speaker)
        }
        add(.tableTopicsEvaluator, instance: 1)
        add(.tableTopicsEvaluator, instance: 2)
        add(.grammarian)
        add(.ahCounter)
        add(.generalEvaluatorFunctionary)
        add(.generalEvaluatorEvaluations)
        add(.timekeeper)
        add(.presidentsClose)

        try? context.save()
        UserDefaults.standard.set(true, forKey: seededKey)
    }
}

/// One role position within a template's agenda.
@Model
final class TemplateSlot {
    /// Stable key of the `Role` this slot fills (see `Role.key`).
    var roleRaw: String = ""
    /// Position in the agenda (ascending).
    var order: Int = 0
    /// Groups repeating roles (e.g. Speaker #2 and its intro/evaluation share
    /// the same instance number). 0 for non-repeating roles.
    var instanceNumber: Int = 0
    /// Optional override for the displayed agenda line. When empty, the label
    /// is derived from the role (e.g. "Speaker #1").
    var customLabel: String = ""

    var template: MeetingTemplate?

    init(roleKey: String, order: Int, instanceNumber: Int = 0, customLabel: String = "") {
        self.roleRaw = roleKey
        self.order = order
        self.instanceNumber = instanceNumber
        self.customLabel = customLabel
    }

    /// Convenience for seeding built-in roles by their `RoleType`.
    convenience init(role: RoleType, order: Int, instanceNumber: Int = 0, customLabel: String = "") {
        self.init(roleKey: role.rawValue, order: order, instanceNumber: instanceNumber, customLabel: customLabel)
    }

    /// The label to display, given the resolved `Role` (which may be nil if the
    /// role was deleted). A custom label always wins.
    func displayLabel(_ role: Role?) -> String {
        if !customLabel.isEmpty { return customLabel }
        return role?.label(instance: instanceNumber) ?? "(deleted role)"
    }
}
