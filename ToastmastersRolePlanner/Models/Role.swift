import Foundation
import SwiftData

/// A role in the club's catalogue. Roles are data (not a fixed list) so they
/// can be viewed, added, edited, and deleted by the user.
///
/// `key` is a stable identifier referenced by `TemplateSlot.roleRaw` and
/// `RoleAssignment.roleRaw`. Built-in roles reuse the old `RoleType` raw values
/// so templates/meetings created before roles became editable still resolve.
@Model
final class Role {
    var key: String = ""
    var name: String = ""
    var symbol: String = "person"
    var green: Int = 60
    var yellow: Int = 90
    var red: Int = 120
    /// Whether the role may appear more than once on one agenda (gets #1, #2…).
    var allowsMultiple: Bool = false
    /// Whether this role appears as a column in the role participation report.
    var showInRolesReport: Bool = true
    /// Whether this role has no person assigned to it in a meeting (e.g. Break).
    var isUnmanned: Bool = false
    var sortOrder: Int = 0

    init(
        key: String,
        name: String,
        symbol: String,
        timing: Timing,
        allowsMultiple: Bool = false,
        showInRolesReport: Bool = true,
        isUnmanned: Bool = false,
        sortOrder: Int = 0
    ) {
        self.key = key
        self.name = name
        self.symbol = symbol
        self.green = timing.green
        self.yellow = timing.yellow
        self.red = timing.red
        self.allowsMultiple = allowsMultiple
        self.showInRolesReport = showInRolesReport
        self.isUnmanned = isUnmanned
        self.sortOrder = sortOrder
    }

    var timing: Timing {
        get { Timing(green: green, yellow: yellow, red: red) }
        set {
            green = newValue.green
            yellow = newValue.yellow
            red = newValue.red
        }
    }

    /// Display label for the role at a given instance (0 for non-repeating).
    func label(instance: Int) -> String {
        allowsMultiple && instance > 0 ? "\(name) #\(instance)" : name
    }
}

extension Role {
    /// Seeds the built-in roles the first time the app runs (when the catalogue
    /// is empty). Default times are migrated from any existing `RoleDefault`
    /// rows so the user's edited defaults carry over.
    static func ensureSeeded(in context: ModelContext) {
        let existing = (try? context.fetch(FetchDescriptor<Role>())) ?? []
        guard existing.isEmpty else { return }

        let priorDefaults = (try? context.fetch(FetchDescriptor<RoleDefault>())) ?? []
        let timingByKey = Dictionary(uniqueKeysWithValues: priorDefaults.map { ($0.roleRaw, $0.timing) })

        for (index, type) in RoleType.allCases.enumerated() {
            context.insert(Role(
                key: type.rawValue,
                name: type.title,
                symbol: type.symbol,
                timing: timingByKey[type.rawValue] ?? type.defaultTiming,
                allowsMultiple: type.allowsMultiple,
                isUnmanned: type.isUnmanned,
                sortOrder: index
            ))
        }
        try? context.save()
    }

    /// A fresh unique key for a user-created role.
    static func newKey() -> String { "custom-" + UUID().uuidString }

    /// Builds a `[key: Role]` lookup for resolving slots/assignments.
    static func lookup(_ roles: [Role]) -> [String: Role] {
        Dictionary(roles.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
    }
}
