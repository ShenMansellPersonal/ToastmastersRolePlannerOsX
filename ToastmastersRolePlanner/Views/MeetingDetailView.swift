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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                detailsCard
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

    private var rolesCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Roles").font(.headline)
                Spacer()
                Text("\(filledCount)/\(mannedCount) filled")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
                                referenceDate: meeting.date
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
                Text("Attendance").font(.headline)
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

    @State private var showingTimes = false

    private var isUnmanned: Bool { role?.isUnmanned ?? false }
    private var defaultTiming: Timing { role?.timing ?? .zero }
    private var effectiveTiming: Timing { assignment.overrideTiming ?? defaultTiming }

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
                    Menu {
                        Button("— Unassigned —") { assignment.assign(nil) }
                        Divider()
                        ForEach(members) { member in
                            Button(memberLabel(member)) { assignment.assign(member) }
                        }
                    } label: {
                        Text(assigneeLabel)
                            .foregroundStyle(assignment.isUnlinkedName ? .secondary : .primary)
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
