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
        /// Meetings in range (from the member's join date) they weren't absent
        /// from — the denominator for the participation-rate page.
        var presentMeetings: Int
    }

    var roleNames: [String]
    var rows: [Row]
    var columnTotals: [Int]
    var grandTotal: Int
    var noRoleTotal: Int
    var absentTotal: Int
    var presentMeetingsTotal: Int
    var start: Date
    var end: Date

    static func build(members: [Member], roles: [Role], meetings: [Meeting], start: Date, end: Date) -> RoleReport {
        let calendar = Calendar.current
        let lo = calendar.startOfDay(for: min(start, end))
        let hi = calendar.startOfDay(for: max(start, end))

        let sortedRoles = roles
            .filter(\.showInRolesReport)
            .sorted { $0.sortOrder < $1.sortOrder }
        // Build the columns. Speaker Introduction and Speaker Evaluation share a
        // single column, so doing both in a meeting counts once.
        func mergedKey(_ key: String) -> String {
            (key == "speakerIntroduction" || key == "speakerEvaluation") ? "speakerIntroEval" : key
        }
        var columnNames: [String] = []
        var indexForKey: [String: Int] = [:]
        var indexForMerged: [String: Int] = [:]
        for role in sortedRoles {
            let merged = mergedKey(role.key)
            if let existing = indexForMerged[merged] {
                indexForKey[role.key] = existing
            } else {
                let column = columnNames.count
                indexForMerged[merged] = column
                indexForKey[role.key] = column
                columnNames.append(merged == "speakerIntroEval" ? "Speaker Intro/Eval" : role.name)
            }
        }

        let activeMembers = members
            .filter(\.isActive)
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        let activeIDs = Set(activeMembers.map(\.persistentModelID))
        var counts: [PersistentIdentifier: [Int]] = [:]
        var noRole: [PersistentIdentifier: Int] = [:]
        var absent: [PersistentIdentifier: Int] = [:]
        var present: [PersistentIdentifier: Int] = [:]
        var joinedDay: [PersistentIdentifier: Date] = [:]
        for member in activeMembers {
            counts[member.persistentModelID] = Array(repeating: 0, count: columnNames.count)
            noRole[member.persistentModelID] = 0
            absent[member.persistentModelID] = 0
            present[member.persistentModelID] = 0
            joinedDay[member.persistentModelID] = calendar.startOfDay(for: member.joinedDate)
        }

        for meeting in meetings {
            let day = calendar.startOfDay(for: meeting.date)
            guard day >= lo, day <= hi else { continue }

            let assignedIDs = Set(meeting.assignments.compactMap { $0.member?.persistentModelID })
            let absentIDs = Set(meeting.absentees.map(\.persistentModelID))

            // Count each (member, role) at most once per meeting, so someone
            // scheduled for the same role twice in a meeting only counts once.
            var countedThisMeeting: [PersistentIdentifier: Set<Int>] = [:]
            for assignment in meeting.assignments {
                guard let member = assignment.member,
                      let index = indexForKey[assignment.roleRaw],
                      counts[member.persistentModelID] != nil
                else { continue }
                let id = member.persistentModelID
                if countedThisMeeting[id, default: []].insert(index).inserted {
                    counts[id]![index] += 1
                }
            }

            for id in activeIDs {
                // Only count attendance-derived stats from the member's join date.
                if let joined = joinedDay[id], day < joined { continue }
                if absentIDs.contains(id) {
                    absent[id]! += 1
                } else {
                    present[id]! += 1   // wasn't absent → present for the rate denominator
                    if !assignedIDs.contains(id) { noRole[id]! += 1 }
                }
            }
        }

        var rows: [Row] = []
        var columnTotals = Array(repeating: 0, count: columnNames.count)
        var noRoleTotal = 0
        var absentTotal = 0
        var presentTotal = 0
        for member in activeMembers {
            let id = member.persistentModelID
            let memberCounts = counts[id] ?? Array(repeating: 0, count: columnNames.count)
            for index in memberCounts.indices { columnTotals[index] += memberCounts[index] }
            let memberNoRole = noRole[id] ?? 0
            let memberAbsent = absent[id] ?? 0
            let memberPresent = present[id] ?? 0
            noRoleTotal += memberNoRole
            absentTotal += memberAbsent
            presentTotal += memberPresent
            rows.append(Row(
                memberName: member.name,
                counts: memberCounts,
                total: memberCounts.reduce(0, +),
                noRole: memberNoRole,
                absent: memberAbsent,
                presentMeetings: memberPresent
            ))
        }

        return RoleReport(
            roleNames: columnNames,
            rows: rows,
            columnTotals: columnTotals,
            grandTotal: columnTotals.reduce(0, +),
            noRoleTotal: noRoleTotal,
            absentTotal: absentTotal,
            presentMeetingsTotal: presentTotal,
            start: lo,
            end: hi
        )
    }
}
