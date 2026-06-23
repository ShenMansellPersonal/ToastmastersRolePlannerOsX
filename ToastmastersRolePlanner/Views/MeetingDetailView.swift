import SwiftUI
import SwiftData

struct MeetingDetailView: View {
    @Bindable var meeting: Meeting

    @Query(sort: \Member.name) private var allMembers: [Member]
    @Query private var roles: [Role]
    @Query private var allAssignments: [RoleAssignment]

    private var rolesByKey: [String: Role] { Role.lookup(roles) }

    private var activeMembers: [Member] {
        allMembers.filter(\.isActive)
    }

    /// For the given role, the most recent prior meeting date on which each
    /// member performed that role. Only meetings before this one are counted,
    /// so the value reads as "days before this meeting they last did the role".
    private func lastPerformedDates(roleKey: String) -> [PersistentIdentifier: Date] {
        var result: [PersistentIdentifier: Date] = [:]
        for assignment in allAssignments {
            guard assignment.roleRaw == roleKey,
                  let member = assignment.member,
                  let otherMeeting = assignment.meeting,
                  otherMeeting.persistentModelID != meeting.persistentModelID,
                  otherMeeting.date < meeting.date
            else { continue }
            let id = member.persistentModelID
            if let existing = result[id], existing >= otherMeeting.date { continue }
            result[id] = otherMeeting.date
        }
        return result
    }

    /// Members assigned to at least one role in this meeting.
    private var assignedMemberIDs: Set<PersistentIdentifier> {
        Set(meeting.assignments.compactMap { $0.member?.persistentModelID })
    }

    /// Members linked to more than one role in this meeting.
    private var duplicateMemberIDs: Set<PersistentIdentifier> {
        var counts: [PersistentIdentifier: Int] = [:]
        for assignment in meeting.assignments {
            if let id = assignment.member?.persistentModelID {
                counts[id, default: 0] += 1
            }
        }
        return Set(counts.filter { $0.value > 1 }.keys)
    }

    private func label(for assignment: RoleAssignment) -> String {
        assignment.displayLabel(rolesByKey[assignment.roleRaw])
    }

    /// Problems worth flagging on this meeting: a member in two roles, or a
    /// member who's both assigned a role and marked absent.
    private var warnings: [String] {
        var result: [String] = []

        // Same member in multiple manned roles.
        var rolesByMember: [PersistentIdentifier: (name: String, labels: [String])] = [:]
        for assignment in meeting.orderedAssignments {
            guard let member = assignment.member, rolesByKey[assignment.roleRaw]?.isUnmanned != true else { continue }
            rolesByMember[member.persistentModelID, default: (member.name, [])].labels.append(label(for: assignment))
        }
        for info in rolesByMember.values where info.labels.count > 1 {
            result.append("\(info.name) is assigned to \(info.labels.count) roles: \(info.labels.joined(separator: ", ")).")
        }
        result.sort()

        // Assigned but marked absent.
        let absentIDs = Set(meeting.absentees.map(\.persistentModelID))
        for assignment in meeting.orderedAssignments {
            guard let member = assignment.member, absentIDs.contains(member.persistentModelID) else { continue }
            result.append("\(member.name) is marked absent but assigned \(label(for: assignment)).")
        }

        return result
    }

    // MARK: Auto-fill

    /// Prior-meeting recency: per member, the last date they did each role and
    /// the last date they did any role. Only meetings before this one count.
    private func priorRecency() -> (perRole: [PersistentIdentifier: [String: Date]], overall: [PersistentIdentifier: Date]) {
        var perRole: [PersistentIdentifier: [String: Date]] = [:]
        var overall: [PersistentIdentifier: Date] = [:]
        for assignment in allAssignments {
            guard let member = assignment.member,
                  let otherMeeting = assignment.meeting,
                  otherMeeting.persistentModelID != meeting.persistentModelID,
                  otherMeeting.date < meeting.date
            else { continue }
            let id = member.persistentModelID
            let date = otherMeeting.date
            if (perRole[id]?[assignment.roleRaw]).map({ date > $0 }) ?? true {
                perRole[id, default: [:]][assignment.roleRaw] = date
            }
            if (overall[id]).map({ date > $0 }) ?? true {
                overall[id] = date
            }
        }
        return (perRole, overall)
    }

    /// Empty, manned role slots that still need someone.
    private var fillableAssignments: [RoleAssignment] {
        meeting.orderedAssignments.filter {
            rolesByKey[$0.roleRaw]?.isUnmanned != true && !$0.isFilled
        }
    }

    /// Fills empty roles, prioritising members who've gone longest without any
    /// role. Never overwrites a set role, never assigns anyone twice, skips
    /// absentees, and places the most-overdue member into the role they're most
    /// overdue for.
    private func autoFill() {
        var remaining = fillableAssignments
        guard !remaining.isEmpty else { return }

        let absentIDs = Set(meeting.absentees.map(\.persistentModelID))
        let (perRole, overall) = priorRecency()

        // Available = active, not absent, not already assigned to any role here.
        var available = activeMembers.filter {
            !absentIDs.contains($0.persistentModelID) && !assignedMemberIDs.contains($0.persistentModelID)
        }
        // Longest since doing any role first (never → first).
        available.sort { lhs, rhs in
            olderFirst(overall[lhs.persistentModelID], overall[rhs.persistentModelID], tieBreak: lhs.name < rhs.name)
        }

        for member in available {
            guard !remaining.isEmpty else { break }
            let memberRoleDates = perRole[member.persistentModelID] ?? [:]
            // Pick the empty role this member is most overdue for.
            guard let chosen = remaining.min(by: { lhs, rhs in
                olderFirst(memberRoleDates[lhs.roleRaw], memberRoleDates[rhs.roleRaw], tieBreak: lhs.order < rhs.order)
            }) else { break }
            chosen.assign(member)
            remaining.removeAll { $0 === chosen }
        }
    }

    /// True when `a` represents a longer gap than `b` (nil = "never" = longest).
    private func olderFirst(_ a: Date?, _ b: Date?, tieBreak: @autoclosure () -> Bool) -> Bool {
        switch (a, b) {
        case (nil, nil): return tieBreak()
        case (nil, _): return true
        case (_, nil): return false
        case let (x?, y?): return x != y ? x < y : tieBreak()
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                detailsCard
                if !warnings.isEmpty {
                    warningsCard
                }
                rolesCard
                attendanceCard
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
        }
        .navigationTitle(meeting.theme.isEmpty ? "Meeting" : meeting.theme)
        .navigationSubtitle(meeting.date.formatted(date: .abbreviated, time: .omitted))
    }

    private var detailsCard: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                DatePicker("Date", selection: $meeting.date, displayedComponents: [.date])
                TextField("Theme", text: $meeting.theme)
                LabeledContent("Template", value: meeting.templateName.isEmpty ? "—" : meeting.templateName)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(6)
        } label: {
            Text("Details").font(.headline)
        }
    }

    private var warningsCard: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(warnings, id: \.self) { warning in
                    Label(warning, systemImage: "exclamationmark.triangle.fill")
                        .font(.callout)
                        .foregroundStyle(.orange)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(6)
        } label: {
            Label("Check these", systemImage: "exclamationmark.triangle")
                .foregroundStyle(.orange)
        }
    }

    private var rolesCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Roles").font(.headline)
                Spacer()
                Text("\(filledCount)/\(mannedCount) filled")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button {
                    autoFill()
                } label: {
                    Label("Auto-fill", systemImage: "wand.and.stars")
                }
                .controlSize(.small)
                .disabled(fillableAssignments.isEmpty)
                .help("Fill empty roles, favouring members who haven't had a role for the longest")
            }

            GroupBox {
                if meeting.assignments.isEmpty {
                    Text("This meeting has no roles.")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(6)
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(meeting.orderedAssignments.enumerated()), id: \.element.persistentModelID) { index, assignment in
                            AssignmentRow(
                                assignment: assignment,
                                role: rolesByKey[assignment.roleRaw],
                                members: activeMembers,
                                lastPerformed: lastPerformedDates(roleKey: assignment.roleRaw),
                                referenceDate: meeting.date,
                                duplicateMemberIDs: duplicateMemberIDs
                            )
                            if index < meeting.assignments.count - 1 {
                                Divider()
                            }
                        }
                    }
                    .padding(6)
                }
            }
        }
    }

    private var attendanceCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Absentees").font(.headline)
                Spacer()
                if !meeting.absentees.isEmpty {
                    Text("\(meeting.absentees.count) marked absent")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            GroupBox {
                if activeMembers.isEmpty {
                    Text("No active members.")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(6)
                } else {
                    VStack(spacing: 6) {
                        ForEach(activeMembers) { member in
                            AbsenteeRow(
                                member: member,
                                isAbsent: meeting.absentees.contains(where: { $0.persistentModelID == member.persistentModelID }),
                                isAssigned: assignedMemberIDs.contains(member.persistentModelID),
                                toggle: { toggleAbsent(member) }
                            )
                        }
                    }
                    .padding(6)
                }
            }
        }
    }

    /// Assignments for roles that take a person (excludes unmanned roles).
    private var mannedAssignments: [RoleAssignment] {
        meeting.assignments.filter { rolesByKey[$0.roleRaw]?.isUnmanned != true }
    }

    private var mannedCount: Int { mannedAssignments.count }

    private var filledCount: Int {
        mannedAssignments.filter { $0.isFilled }.count
    }

    private func toggleAbsent(_ member: Member) {
        if let index = meeting.absentees.firstIndex(where: { $0.persistentModelID == member.persistentModelID }) {
            meeting.absentees.remove(at: index)
        } else {
            meeting.absentees.append(member)
        }
    }
}

// MARK: - Rows

private struct AssignmentRow: View {
    @Bindable var assignment: RoleAssignment
    let role: Role?
    let members: [Member]
    /// Most recent prior date each member performed this role (see MeetingDetailView).
    let lastPerformed: [PersistentIdentifier: Date]
    /// This meeting's date — recency is measured back from here.
    let referenceDate: Date
    /// Members linked to more than one role in this meeting (flagged as clashes).
    let duplicateMemberIDs: Set<PersistentIdentifier>

    @State private var showingTimes = false

    private var isUnmanned: Bool { role?.isUnmanned ?? false }
    private var defaultTiming: Timing { role?.timing ?? .zero }
    private var effectiveTiming: Timing { assignment.overrideTiming ?? defaultTiming }
    private var isDuplicate: Bool {
        guard let id = assignment.member?.persistentModelID else { return false }
        return duplicateMemberIDs.contains(id)
    }

    /// Members ordered by how long since they last did this role: never first,
    /// then longest-ago to most-recent.
    private var sortedMembers: [Member] {
        members.sorted { lhs, rhs in
            switch (lastPerformed[lhs.persistentModelID], lastPerformed[rhs.persistentModelID]) {
            case (nil, nil): return lhs.name < rhs.name
            case (nil, _): return true
            case (_, nil): return false
            case let (a?, b?): return a != b ? a < b : lhs.name < rhs.name
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label {
                    Text(assignment.displayLabel(role))
                } icon: {
                    Image(systemName: role?.symbol ?? "questionmark.circle")
                        .foregroundStyle(.tint)
                }

                Spacer()

                if !isUnmanned {
                    if isDuplicate {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                            .help("This member is assigned to more than one role")
                    }
                    Menu {
                        Button("— Unassigned —") { assignment.assign(nil) }
                        Divider()
                        ForEach(sortedMembers) { member in
                            Button(memberLabel(member)) { assignment.assign(member) }
                        }
                    } label: {
                        Text(assigneeLabel)
                            .foregroundStyle(isDuplicate ? .orange : (assignment.isUnlinkedName ? .secondary : .primary))
                    }
                    .frame(maxWidth: 240)
                }
            }

            HStack(spacing: 12) {
                TimingSummary(timing: effectiveTiming, isCustom: assignment.hasTimingOverride)

                Spacer()

                Button(showingTimes ? "Done" : (assignment.hasTimingOverride ? "Edit times" : "Override times")) {
                    if !showingTimes && !assignment.hasTimingOverride {
                        // Seed the override from the current default so editing starts there.
                        assignment.setOverride(defaultTiming)
                    }
                    showingTimes.toggle()
                }
                .buttonStyle(.link)
                .font(.caption)

                if assignment.hasTimingOverride {
                    Button("Reset") {
                        assignment.setOverride(nil)
                        showingTimes = false
                    }
                    .buttonStyle(.link)
                    .font(.caption)
                }
            }

            if showingTimes {
                TimingEditor(timing: Binding(
                    get: { assignment.overrideTiming ?? defaultTiming },
                    set: { assignment.setOverride($0) }
                ))
            }
        }
        .padding(.vertical, 2)
    }

    /// What the menu button shows: the linked member, an unlinked text name
    /// flagged "not in list", or unassigned.
    private var assigneeLabel: String {
        if let member = assignment.member { return member.name }
        if assignment.isUnlinkedName { return "\(assignment.memberName) · not in list" }
        return "— Unassigned —"
    }

    /// "Name · 14d ago" / "Name · today" / "Name · never" — recency of when this
    /// member last performed this role, measured back from the meeting date.
    private func memberLabel(_ member: Member) -> String {
        let suffix: String
        if let last = lastPerformed[member.persistentModelID] {
            let calendar = Calendar.current
            let days = calendar.dateComponents(
                [.day],
                from: calendar.startOfDay(for: last),
                to: calendar.startOfDay(for: referenceDate)
            ).day ?? 0
            suffix = days <= 0 ? "today" : "\(days)d ago"
        } else {
            suffix = "never"
        }
        return "\(member.name) · \(suffix)"
    }
}

private struct AbsenteeRow: View {
    let member: Member
    let isAbsent: Bool
    let isAssigned: Bool
    let toggle: () -> Void

    var body: some View {
        HStack {
            Toggle(isOn: Binding(get: { isAbsent }, set: { _ in toggle() })) {
                Text(member.name)
            }
            .toggleStyle(.checkbox)

            if isAssigned && isAbsent {
                Label("Assigned but absent", systemImage: "exclamationmark.triangle.fill")
                    .labelStyle(.iconOnly)
                    .foregroundStyle(.orange)
                    .help("This member is marked absent but still has a role.")
            }
            Spacer()
        }
    }
}

#Preview {
    NavigationStack {
        MeetingDetailView(meeting: PreviewData.sampleMeeting)
    }
    .modelContainer(PreviewData.container)
}
