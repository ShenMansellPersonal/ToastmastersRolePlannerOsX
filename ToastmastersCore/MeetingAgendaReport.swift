import Foundation
import SwiftData

/// One meeting's running agenda: each role with its scheduled start time (the
/// clock advances by each role's red/maximum time) and its signal times.
struct MeetingAgenda: Identifiable {
    let id = UUID()
    var date: Date
    var theme: String
    var rows: [Row]
    var noRole: [String]       // active members with no role (and not absent)
    var apologies: [String]    // members marked absent

    struct Row: Identifiable {
        let id = UUID()
        var startSeconds: Int   // seconds since midnight
        var roleLabel: String
        var user: String        // empty if unmanned
        var green: Int
        var yellow: Int
        var red: Int
        var isBreak: Bool       // the Break gets extra spacing / a divider
    }
}

enum MeetingAgendaReport {
    /// 7:15 pm.
    static let defaultStartSeconds = 19 * 3600 + 15 * 60

    static func build(
        meetings: [Meeting],
        rolesByKey: [String: Role],
        activeMembers: [Member],
        start: Date,
        end: Date,
        meetingStartSeconds: Int = defaultStartSeconds
    ) -> [MeetingAgenda] {
        let calendar = Calendar.current
        let lo = calendar.startOfDay(for: min(start, end))
        let hi = calendar.startOfDay(for: max(start, end))

        let inRange = meetings
            .filter { let day = calendar.startOfDay(for: $0.date); return day >= lo && day <= hi }
            .sorted { $0.date < $1.date }

        return inRange.map { meeting in
            var clock = meetingStartSeconds
            var contentElapsed = 0   // role time so far (drives the breathing-room buffer)
            var buffersAdded = 0     // minutes of buffer already added
            var rows: [MeetingAgenda.Row] = []

            for assignment in meeting.orderedAssignments {
                let role = rolesByKey[assignment.roleRaw]
                let user = assignment.assigneeName ?? ""
                let isUnmanned = role?.isUnmanned ?? false
                // Skip unassigned manned roles entirely — no row and no time.
                if user.isEmpty && !isUnmanned { continue }

                let red = role?.red ?? 0
                rows.append(MeetingAgenda.Row(
                    startSeconds: clock,
                    roleLabel: assignment.displayLabel(role),
                    user: user,
                    green: role?.green ?? 0,
                    yellow: role?.yellow ?? 0,
                    red: red,
                    isBreak: role?.key == "breakTime"
                ))

                clock += red
                contentElapsed += red
                // Add a minute of breathing room for each completed 10 minutes;
                // it shifts the next role's start but isn't shown as a row.
                let bufferDue = contentElapsed / 600
                if bufferDue > buffersAdded {
                    clock += (bufferDue - buffersAdded) * 60
                    buffersAdded = bufferDue
                }
            }

            let assigned = Set(meeting.assignments.compactMap { $0.member?.persistentModelID })
            let absentIDs = Set(meeting.absentees.map(\.persistentModelID))
            let noRole = activeMembers
                .filter { !assigned.contains($0.persistentModelID) && !absentIDs.contains($0.persistentModelID) }
                .map(\.name)
            let apologies = meeting.absentees.map(\.name).sorted()

            return MeetingAgenda(date: meeting.date, theme: meeting.theme, rows: rows, noRole: noRole, apologies: apologies)
        }
    }
}
