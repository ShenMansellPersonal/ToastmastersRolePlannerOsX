import Foundation
import SwiftData

/// A matrix of how many times each current (active) member performed each role
/// within a date range. Built from meetings whose date falls in [start, end].
struct RoleReport {
    struct Row: Identifiable {
        let id = UUID()
        var memberName: String
        var counts: [Int]   // one per role, aligned with `roleNames`
        var total: Int      // sum of role counts
        var noRole: Int     // meetings attended (not absent) with no role
        var absent: Int     // meetings marked absent
    }

    var roleNames: [String]
    var rows: [Row]
    var columnTotals: [Int]
    var grandTotal: Int
    var noRoleTotal: Int
    var absentTotal: Int
    var start: Date
    var end: Date

    static func build(members: [Member], roles: [Role], meetings: [Meeting], start: Date, end: Date) -> RoleReport {
        let calendar = Calendar.current
        let lo = calendar.startOfDay(for: min(start, end))
        let hi = calendar.startOfDay(for: max(start, end))

        let sortedRoles = roles
            .filter(\.showInRolesReport)
            .sorted { $0.sortOrder < $1.sortOrder }
        let roleKeys = sortedRoles.map(\.key)
        let indexForKey = Dictionary(uniqueKeysWithValues: roleKeys.enumerated().map { ($1, $0) })

        let activeMembers = members
            .filter(\.isActive)
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        let activeIDs = Set(activeMembers.map(\.persistentModelID))
        var counts: [PersistentIdentifier: [Int]] = [:]
        var noRole: [PersistentIdentifier: Int] = [:]
        var absent: [PersistentIdentifier: Int] = [:]
        var joinedDay: [PersistentIdentifier: Date] = [:]
        for member in activeMembers {
            counts[member.persistentModelID] = Array(repeating: 0, count: roleKeys.count)
            noRole[member.persistentModelID] = 0
            absent[member.persistentModelID] = 0
            joinedDay[member.persistentModelID] = calendar.startOfDay(for: member.joinedDate)
        }

        for meeting in meetings {
            let day = calendar.startOfDay(for: meeting.date)
            guard day >= lo, day <= hi else { continue }

            let assignedIDs = Set(meeting.assignments.compactMap { $0.member?.persistentModelID })
            let absentIDs = Set(meeting.absentees.map(\.persistentModelID))

            for assignment in meeting.assignments {
                guard let member = assignment.member,
                      let index = indexForKey[assignment.roleRaw],
                      counts[member.persistentModelID] != nil
                else { continue }
                counts[member.persistentModelID]![index] += 1
            }

            for id in activeIDs {
                // Only count attendance-derived stats from the member's join date.
                if let joined = joinedDay[id], day < joined { continue }
                if absentIDs.contains(id) {
                    absent[id]! += 1
                } else if !assignedIDs.contains(id) {
                    noRole[id]! += 1
                }
            }
        }

        var rows: [Row] = []
        var columnTotals = Array(repeating: 0, count: roleKeys.count)
        var noRoleTotal = 0
        var absentTotal = 0
        for member in activeMembers {
            let id = member.persistentModelID
            let memberCounts = counts[id] ?? Array(repeating: 0, count: roleKeys.count)
            for index in memberCounts.indices { columnTotals[index] += memberCounts[index] }
            let memberNoRole = noRole[id] ?? 0
            let memberAbsent = absent[id] ?? 0
            noRoleTotal += memberNoRole
            absentTotal += memberAbsent
            rows.append(Row(
                memberName: member.name,
                counts: memberCounts,
                total: memberCounts.reduce(0, +),
                noRole: memberNoRole,
                absent: memberAbsent
            ))
        }

        return RoleReport(
            roleNames: sortedRoles.map(\.name),
            rows: rows,
            columnTotals: columnTotals,
            grandTotal: columnTotals.reduce(0, +),
            noRoleTotal: noRoleTotal,
            absentTotal: absentTotal,
            start: lo,
            end: hi
        )
    }
}
