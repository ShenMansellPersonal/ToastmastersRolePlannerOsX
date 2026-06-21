import Foundation
import SwiftData

/// Green / yellow / red signal times for a role, in seconds.
struct Timing: Equatable, Hashable {
    var green: Int
    var yellow: Int
    var red: Int

    static let zero = Timing(green: 0, yellow: 0, red: 0)
}

extension Int {
    /// Formats a seconds count as "M:SS".
    var asMMSS: String {
        let minutes = self / 60
        let seconds = self % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

/// The editable, per-role default signal times — one row per `RoleType`.
/// Seeded from the built-in `RoleType.defaultTiming` values on first launch.
@Model
final class RoleDefault {
    /// Raw value of the `RoleType`. Effectively unique.
    var roleRaw: String = ""
    var green: Int = 0
    var yellow: Int = 0
    var red: Int = 0

    init(role: RoleType, timing: Timing) {
        self.roleRaw = role.rawValue
        self.green = timing.green
        self.yellow = timing.yellow
        self.red = timing.red
    }

    var role: RoleType { RoleType(rawValue: roleRaw) ?? .toastmaster }

    var timing: Timing {
        get { Timing(green: green, yellow: yellow, red: red) }
        set {
            green = newValue.green
            yellow = newValue.yellow
            red = newValue.red
        }
    }

    /// Inserts a `RoleDefault` for any role that doesn't have one yet, using the
    /// built-in defaults. Safe to call repeatedly (e.g. after adding a new role).
    static func ensureSeeded(in context: ModelContext) {
        let existing = (try? context.fetch(FetchDescriptor<RoleDefault>())) ?? []
        let known = Set(existing.map(\.roleRaw))
        var inserted = false
        for role in RoleType.allCases where !known.contains(role.rawValue) {
            context.insert(RoleDefault(role: role, timing: role.defaultTiming))
            inserted = true
        }
        if inserted { try? context.save() }
    }

    /// The default timing for a role, taken from the editable store when present
    /// and otherwise from the built-in defaults.
    static func timing(for role: RoleType, in defaults: [RoleDefault]) -> Timing {
        defaults.first(where: { $0.roleRaw == role.rawValue })?.timing ?? role.defaultTiming
    }
}
