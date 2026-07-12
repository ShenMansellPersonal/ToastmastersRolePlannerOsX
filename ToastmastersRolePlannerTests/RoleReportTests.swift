import XCTest
import SwiftData

@MainActor
final class RoleReportTests: XCTestCase {

    // MARK: Helpers

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([
            Member.self, MeetingTemplate.self, TemplateSlot.self,
            Meeting.self, RoleAssignment.self, Role.self, RoleDefault.self
        ])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [config])
    }

    private func day(_ year: Int, _ month: Int, _ dayOfMonth: Int) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = dayOfMonth
        return Calendar.current.date(from: components)!
    }

    @discardableResult
    private func addRole(_ context: ModelContext, key: String, name: String, multiple: Bool = false, order: Int) -> Role {
        let role = Role(key: key, name: name, symbol: "person",
                        timing: Timing(green: 60, yellow: 90, red: 120),
                        allowsMultiple: multiple, sortOrder: order)
        context.insert(role)
        return role
    }

    @discardableResult
    private func addMember(_ context: ModelContext, _ name: String, active: Bool = true, joined: Date) -> Member {
        let member = Member(name: name, isActive: active, joinedDate: joined)
        context.insert(member)
        return member
    }

    @discardableResult
    private func addMeeting(_ context: ModelContext, on date: Date,
                            assignments: [(String, Member?)],
                            absentees: [Member] = []) -> Meeting {
        let meeting = Meeting(date: date)
        meeting.assignments = assignments.enumerated().map { index, pair in
            RoleAssignment(roleKey: pair.0, order: index, member: pair.1)
        }
        meeting.absentees = absentees
        context.insert(meeting)
        return meeting
    }

    private func fetchMeetings(_ context: ModelContext) throws -> [Meeting] {
        try context.fetch(FetchDescriptor<Meeting>())
    }

    private func row(_ report: RoleReport, _ name: String) -> RoleReport.Row {
        report.rows.first { $0.memberName == name }!
    }

    // MARK: Tests

    func testCountsRolesAndAggregatesInstances() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let toastmaster = addRole(context, key: "toastmaster", name: "Toastmaster", order: 0)
        let speaker = addRole(context, key: "speaker", name: "Speaker", multiple: true, order: 1)
        let alex = addMember(context, "Alex", joined: day(2025, 1, 1))
        let bryn = addMember(context, "Bryn", joined: day(2025, 1, 1))

        // Alex: toastmaster + two speaker slots in one meeting; one more speaker next week.
        addMeeting(context, on: day(2025, 3, 1),
                   assignments: [("toastmaster", alex), ("speaker", alex), ("speaker", bryn)])
        addMeeting(context, on: day(2025, 3, 8), assignments: [("speaker", alex)])

        let report = RoleReport.build(
            members: [alex, bryn], roles: [toastmaster, speaker],
            meetings: try fetchMeetings(context),
            start: day(2025, 1, 1), end: day(2025, 12, 31)
        )

        XCTAssertEqual(report.roleNames, ["Toastmaster", "Speaker"])
        XCTAssertEqual(row(report, "Alex").counts, [1, 2])   // Speaker #1 + a later speech
        XCTAssertEqual(row(report, "Alex").total, 3)
        XCTAssertEqual(row(report, "Bryn").counts, [0, 1])
        XCTAssertEqual(report.columnTotals, [1, 3])
        XCTAssertEqual(report.grandTotal, 4)
    }

    func testSameRoleTwiceInMeetingCountsOnce() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let toastmaster = addRole(context, key: "toastmaster", name: "Toastmaster", order: 0)
        let speaker = addRole(context, key: "speaker", name: "Speaker", multiple: true, order: 1)
        let alex = addMember(context, "Alex", joined: day(2025, 1, 1))

        // Same role twice (both Toastmaster slots) + the same role at two
        // instances (Speaker #1 and #2) in one meeting.
        addMeeting(context, on: day(2025, 3, 1), assignments: [
            ("toastmaster", alex), ("toastmaster", alex),
            ("speaker", alex), ("speaker", alex)
        ])

        let report = RoleReport.build(
            members: [alex], roles: [toastmaster, speaker],
            meetings: try fetchMeetings(context),
            start: day(2025, 1, 1), end: day(2025, 12, 31)
        )

        XCTAssertEqual(row(report, "Alex").counts, [1, 1])   // each role counted once
        XCTAssertEqual(row(report, "Alex").total, 2)
    }

    func testIntroAndEvalShareOneColumnCountedOncePerMeeting() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let intro = addRole(context, key: "speakerIntroduction", name: "Speaker Introduction", multiple: true, order: 0)
        let eval = addRole(context, key: "speakerEvaluation", name: "Speaker Evaluation", multiple: true, order: 1)
        let alex = addMember(context, "Alex", joined: day(2025, 1, 1))

        // Intro + eval in one meeting → one credit; eval again next week → another.
        addMeeting(context, on: day(2025, 3, 1), assignments: [("speakerIntroduction", alex), ("speakerEvaluation", alex)])
        addMeeting(context, on: day(2025, 3, 8), assignments: [("speakerEvaluation", alex)])

        let report = RoleReport.build(
            members: [alex], roles: [intro, eval],
            meetings: try fetchMeetings(context),
            start: day(2025, 1, 1), end: day(2025, 12, 31)
        )

        XCTAssertEqual(report.roleNames, ["Speaker Intro/Eval"])
        XCTAssertEqual(row(report, "Alex").counts, [2])   // one per meeting
    }

    func testNoRoleAndAbsentCounts() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let toastmaster = addRole(context, key: "toastmaster", name: "Toastmaster", order: 0)
        let alex = addMember(context, "Alex", joined: day(2025, 1, 1))
        let bryn = addMember(context, "Bryn", joined: day(2025, 1, 1))

        addMeeting(context, on: day(2025, 3, 1), assignments: [("toastmaster", alex)])           // Bryn: no role
        addMeeting(context, on: day(2025, 3, 8), assignments: [("toastmaster", alex)], absentees: [bryn]) // Bryn: absent
        addMeeting(context, on: day(2025, 3, 15), assignments: [])                                // both: no role

        let report = RoleReport.build(
            members: [alex, bryn], roles: [toastmaster],
            meetings: try fetchMeetings(context),
            start: day(2025, 1, 1), end: day(2025, 12, 31)
        )

        let alexRow = row(report, "Alex")
        XCTAssertEqual(alexRow.counts, [2])
        XCTAssertEqual(alexRow.noRole, 1)   // only the empty meeting
        XCTAssertEqual(alexRow.absent, 0)

        let brynRow = row(report, "Bryn")
        XCTAssertEqual(brynRow.counts, [0])
        XCTAssertEqual(brynRow.noRole, 2)   // meeting 1 and 3
        XCTAssertEqual(brynRow.absent, 1)   // meeting 2

        XCTAssertEqual(report.noRoleTotal, 3)
        XCTAssertEqual(report.absentTotal, 1)
    }

    /// Reproduces the reported bug: an absent member must never be counted as
    /// "no role", even in a meeting that also has Table Topics speakers ticked
    /// (a second Meeting→Member relationship that could confuse the absentees).
    func testAbsentNotCountedAsNoRoleWithTableTopics() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let toastmaster = addRole(context, key: "toastmaster", name: "Toastmaster", order: 0)
        let alex = addMember(context, "Alex", joined: day(2025, 1, 1))
        let bryn = addMember(context, "Bryn", joined: day(2025, 1, 1))

        // Bryn is absent; Alex is toastmaster and is ticked as a TT speaker.
        let meeting = addMeeting(context, on: day(2025, 3, 1),
                                 assignments: [("toastmaster", alex)], absentees: [bryn])
        meeting.tableTopicsSpeakers = [alex]

        let report = RoleReport.build(
            members: [alex, bryn], roles: [toastmaster],
            meetings: try fetchMeetings(context),
            start: day(2025, 1, 1), end: day(2025, 12, 31)
        )

        let brynRow = row(report, "Bryn")
        XCTAssertEqual(brynRow.absent, 1)
        XCTAssertEqual(brynRow.noRole, 0)              // absent ⇒ not "no role"
        XCTAssertEqual(brynRow.presentMeetings, 0)     // absent ⇒ not present
        XCTAssertEqual(row(report, "Alex").ttSpeaker, 1)
    }

    func testNoRoleRespectsJoinedDate() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let toastmaster = addRole(context, key: "toastmaster", name: "Toastmaster", order: 0)
        let carol = addMember(context, "Carol", joined: day(2025, 6, 1))

        addMeeting(context, on: day(2025, 3, 1), assignments: [])   // before Carol joined
        addMeeting(context, on: day(2025, 7, 1), assignments: [])   // after Carol joined

        let report = RoleReport.build(
            members: [carol], roles: [toastmaster],
            meetings: try fetchMeetings(context),
            start: day(2025, 1, 1), end: day(2025, 12, 31)
        )

        XCTAssertEqual(row(report, "Carol").noRole, 1)   // only the post-join meeting
    }

    func testDateRangeExcludesOutsideMeetings() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let toastmaster = addRole(context, key: "toastmaster", name: "Toastmaster", order: 0)
        let alex = addMember(context, "Alex", joined: day(2024, 1, 1))

        addMeeting(context, on: day(2024, 12, 1), assignments: [("toastmaster", alex)]) // before range
        addMeeting(context, on: day(2025, 5, 1), assignments: [("toastmaster", alex)])  // in range

        let report = RoleReport.build(
            members: [alex], roles: [toastmaster],
            meetings: try fetchMeetings(context),
            start: day(2025, 1, 1), end: day(2025, 12, 31)
        )

        XCTAssertEqual(row(report, "Alex").counts, [1])
    }

    func testInactiveMembersExcluded() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let toastmaster = addRole(context, key: "toastmaster", name: "Toastmaster", order: 0)
        let active = addMember(context, "Active", active: true, joined: day(2025, 1, 1))
        let former = addMember(context, "Former", active: false, joined: day(2025, 1, 1))

        addMeeting(context, on: day(2025, 4, 1), assignments: [("toastmaster", former)])

        let report = RoleReport.build(
            members: [active, former], roles: [toastmaster],
            meetings: try fetchMeetings(context),
            start: day(2025, 1, 1), end: day(2025, 12, 31)
        )

        XCTAssertEqual(report.rows.count, 1)
        XCTAssertEqual(report.rows.first?.memberName, "Active")
    }

    func testUnlinkedHistoricNameNotCounted() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let toastmaster = addRole(context, key: "toastmaster", name: "Toastmaster", order: 0)
        let alex = addMember(context, "Alex", joined: day(2025, 1, 1))

        // A text-only assignee (former member, no linked Member) plus Alex with no role.
        let meeting = addMeeting(context, on: day(2025, 4, 1), assignments: [])
        let historic = RoleAssignment(roleKey: "toastmaster", order: 0, memberName: "Guest Speaker")
        meeting.assignments = [historic]

        let report = RoleReport.build(
            members: [alex], roles: [toastmaster],
            meetings: try fetchMeetings(context),
            start: day(2025, 1, 1), end: day(2025, 12, 31)
        )

        // No current member performed the role; Alex attended without one.
        XCTAssertEqual(report.columnTotals, [0])
        XCTAssertEqual(row(report, "Alex").noRole, 1)
    }
}
