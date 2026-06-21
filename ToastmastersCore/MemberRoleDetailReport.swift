import Foundation
import SwiftData

/// For each current member, how many days since they last performed each
/// (manned) role — or "never". Measured back from `asOf`.
struct MemberRoleDetailReport {
    struct RoleEntry: Identifiable {
        let id = UUID()
        var roleName: String
        var daysAgo: Int?   // nil = never performed
    }

    struct MemberSection: Identifiable {
        let id = UUID()
        var memberName: String
        var entries: [RoleEntry]
    }

    var sections: [MemberSection]
    var asOf: Date

    static func build(members: [Member], roles: [Role], meetings: [Meeting], asOf: Date) -> MemberRoleDetailReport {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: asOf)

        let reportRoles = roles
            .filter { !$0.isUnmanned }
            .sorted { $0.sortOrder < $1.sortOrder }

        let activeMembers = members
            .filter(\.isActive)
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        let activeIDs = Set(activeMembers.map(\.persistentModelID))

        // Most recent meeting day (on/before today) each member did each role.
        var lastDate: [PersistentIdentifier: [String: Date]] = [:]
        for member in activeMembers { lastDate[member.persistentModelID] = [:] }

        for meeting in meetings {
            let day = calendar.startOfDay(for: meeting.date)
            guard day <= today else { continue }
            for assignment in meeting.assignments {
                guard let member = assignment.member, activeIDs.contains(member.persistentModelID) else { continue }
                let id = member.persistentModelID
                if let existing = lastDate[id]?[assignment.roleRaw], existing >= day { continue }
                lastDate[id]?[assignment.roleRaw] = day
            }
        }

        var sections: [MemberSection] = []
        for member in activeMembers {
            let performed = lastDate[member.persistentModelID] ?? [:]
            let entries = reportRoles.map { role -> RoleEntry in
                guard let date = performed[role.key] else {
                    return RoleEntry(roleName: role.name, daysAgo: nil)
                }
                let days = calendar.dateComponents([.day], from: date, to: today).day ?? 0
                return RoleEntry(roleName: role.name, daysAgo: max(0, days))
            }
            sections.append(MemberSection(memberName: member.name, entries: entries))
        }

        return MemberRoleDetailReport(sections: sections, asOf: today)
    }
}
