import Foundation
import SwiftData

/// How often each active member spoke during Table Topics within a date range,
/// and the rate at which they did so among the meetings they attended.
struct TableTopicsReport {
    struct Row: Identifiable {
        let id = UUID()
        var memberName: String
        var ttCount: Int          // meetings in range they spoke at Table Topics
        var presentMeetings: Int  // meetings in range (from join date) they weren't absent from
        /// ttCount / presentMeetings, as a percentage; nil when they attended none.
        var rate: Double? {
            presentMeetings > 0 ? Double(ttCount) / Double(presentMeetings) * 100 : nil
        }
    }

    var rows: [Row]
    var meetingCount: Int   // meetings falling within the range
    var start: Date
    var end: Date

    /// The report's default range: 29 June 2026 or six months ago, whichever is
    /// more recent, through the day before today.
    static func defaultRange(now: Date = Date()) -> (start: Date, end: Date) {
        let calendar = Calendar.current
        let sixMonthsAgo = calendar.date(byAdding: .month, value: -6, to: now) ?? now
        let jun29_2026 = calendar.date(from: DateComponents(year: 2026, month: 6, day: 29)) ?? sixMonthsAgo
        let start = max(jun29_2026, sixMonthsAgo)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: now)) ?? now
        return (calendar.startOfDay(for: start), yesterday)
    }

    static func build(members: [Member], meetings: [Meeting], start: Date, end: Date) -> TableTopicsReport {
        let calendar = Calendar.current
        let lo = calendar.startOfDay(for: min(start, end))
        let hi = calendar.startOfDay(for: max(start, end))

        let activeMembers = members
            .filter(\.isActive)
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        let activeIDs = Set(activeMembers.map(\.persistentModelID))
        var ttCount: [PersistentIdentifier: Int] = [:]
        var present: [PersistentIdentifier: Int] = [:]
        var joinedDay: [PersistentIdentifier: Date] = [:]
        for member in activeMembers {
            ttCount[member.persistentModelID] = 0
            present[member.persistentModelID] = 0
            joinedDay[member.persistentModelID] = calendar.startOfDay(for: member.joinedDate)
        }

        var meetingCount = 0
        for meeting in meetings {
            let day = calendar.startOfDay(for: meeting.date)
            guard day >= lo, day <= hi else { continue }
            meetingCount += 1

            let absentIDs = Set(meeting.absentees.map(\.persistentModelID))
            let ttIDs = Set(meeting.tableTopicsSpeakers.map(\.persistentModelID))

            for id in activeIDs {
                // Only count from the member's join date onward.
                if let joined = joinedDay[id], day < joined { continue }
                if absentIDs.contains(id) { continue }   // absent → not present, can't have spoken
                present[id]! += 1
                if ttIDs.contains(id) { ttCount[id]! += 1 }
            }
        }

        let rows = activeMembers.map { member in
            let id = member.persistentModelID
            return Row(
                memberName: member.name,
                ttCount: ttCount[id] ?? 0,
                presentMeetings: present[id] ?? 0
            )
        }
        // Lowest pick rate first (a missing rate reads as 0%); ties broken by name.
        .sorted {
            let lhs = $0.rate ?? 0, rhs = $1.rate ?? 0
            if lhs != rhs { return lhs < rhs }
            return $0.memberName.localizedCaseInsensitiveCompare($1.memberName) == .orderedAscending
        }

        return TableTopicsReport(rows: rows, meetingCount: meetingCount, start: lo, end: hi)
    }
}
