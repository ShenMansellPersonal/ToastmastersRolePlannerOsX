import Foundation
import SwiftData

/// For each current member, how many days since they last performed each
/// role shown in the role participation report — or "never". Uses the same
/// role set and merging as that report. Measured back from `asOf`.
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

        let sortedRoles = roles
            .filter(\.showInRolesReport)
            .sorted { $0.sortOrder < $1.sortOrder }

        // Speaker Introduction and Speaker Evaluation share a single row, so
        // doing either counts towards the same "Speaker Intro/Eval" entry —
        // matching the role participation report.
        func mergedKey(_ key: String) -> String {
            (key == "speakerIntroduction" || key == "speakerEvaluation") ? "speakerIntroEval" : key
        }
        // Ordered display columns and the map from each role key to its column.
        var columns: [(name: String, key: String)] = []
        var keyForRole: [String: String] = [:]
        var seenMerged = Set<String>()
        for role in sortedRoles {
            let merged = mergedKey(role.key)
            keyForRole[role.key] = merged
            if seenMerged.insert(merged).inserted {
                columns.append((merged == "speakerIntroEval" ? "Speaker Intro/Eval" : role.name, merged))
            }
        }

        let activeMembers = members
            .filter(\.isActive)
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        let activeIDs = Set(activeMembers.map(\.persistentModelID))

        // Most recent meeting day (on/before today) each member did each column.
        var lastDate: [PersistentIdentifier: [String: Date]] = [:]
        for member in activeMembers { lastDate[member.persistentModelID] = [:] }

        for meeting in meetings {
            let day = calendar.startOfDay(for: meeting.date)
            guard day <= today else { continue }
            for assignment in meeting.assignments {
                guard let member = assignment.member, activeIDs.contains(member.persistentModelID),
                      let key = keyForRole[assignment.roleRaw] else { continue }
                let id = member.persistentModelID
                if let existing = lastDate[id]?[key], existing >= day { continue }
                lastDate[id]?[key] = day
            }
        }

        var sections: [MemberSection] = []
        for member in activeMembers {
            let performed = lastDate[member.persistentModelID] ?? [:]
            let entries = columns.map { column -> RoleEntry in
                guard let date = performed[column.key] else {
                    return RoleEntry(roleName: column.name, daysAgo: nil)
                }
                let days = calendar.dateComponents([.day], from: date, to: today).day ?? 0
                return RoleEntry(roleName: column.name, daysAgo: max(0, days))
            }
            sections.append(MemberSection(memberName: member.name, entries: entries))
        }

        return MemberRoleDetailReport(sections: sections, asOf: today)
    }
}
