import Foundation

/// "Long" (tidy) CSV of every meeting's roster — one row per assignment, plus
/// rows for members with no role and apologies. Suited to a spreadsheet that
/// filters/pivots by date, so meetings with different role sets fit cleanly.
enum RosterCSV {
    static let header = "Date,Theme,Order,Role,Person,Status"

    static func export(meetings: [Meeting], activeMembers: [Member], rolesByKey: [String: Role]) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"

        var lines = [header]
        for meeting in meetings.sorted(by: { $0.date < $1.date }) {
            let date = formatter.string(from: meeting.date)
            let theme = meeting.theme

            for assignment in meeting.orderedAssignments {
                let role = rolesByKey[assignment.roleRaw]
                if role?.isUnmanned == true { continue }   // unmanned roles have no person
                let person = assignment.assigneeName ?? "unassigned"
                lines.append(row(date, theme, "\(assignment.order)", assignment.displayLabel(role), person, "role"))
            }

            let assigned = Set(meeting.assignments.compactMap { $0.member?.persistentModelID })
            let absent = Set(meeting.absentees.map(\.persistentModelID))
            for member in activeMembers where !assigned.contains(member.persistentModelID) && !absent.contains(member.persistentModelID) {
                lines.append(row(date, theme, "900", "(no role)", member.name, "no role"))
            }
            for member in meeting.absentees {
                lines.append(row(date, theme, "990", "(apology)", member.name, "apology"))
            }
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private static func row(_ fields: String...) -> String {
        fields.map(escape).joined(separator: ",")
    }

    private static func escape(_ field: String) -> String {
        if field.contains(",") || field.contains("\"") || field.contains("\n") || field.contains("\r") {
            return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return field
    }
}
