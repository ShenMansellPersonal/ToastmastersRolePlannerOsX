import SwiftUI
import SwiftData

struct MeetingDetailView: View {
    @Bindable var meeting: Meeting

    @Query(sort: \Member.name) private var allMembers: [Member]
    @Query private var roles: [Role]

    private var rolesByKey: [String: Role] { Role.lookup(roles) }

    private var activeMembers: [Member] {
        allMembers.filter(\.isActive)
    }

    /// Members assigned to at least one role in this meeting.
    private var assignedMemberIDs: Set<PersistentIdentifier> {
        Set(meeting.assignments.compactMap { $0.member?.persistentModelID })
    }

    var body: some View {
        Form {
            Section("Details") {
                DatePicker("Date", selection: $meeting.date, displayedComponents: [.date])
                TextField("Theme", text: $meeting.theme)
                LabeledContent("Template", value: meeting.templateName.isEmpty ? "—" : meeting.templateName)
            }

            Section {
                if meeting.assignments.isEmpty {
                    Text("This meeting has no roles.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(meeting.orderedAssignments) { assignment in
                        AssignmentRow(
                            assignment: assignment,
                            role: rolesByKey[assignment.roleRaw],
                            members: activeMembers
                        )
                    }
                }
            } header: {
                HStack {
                    Text("Roles")
                    Spacer()
                    Text("\(filledCount)/\(meeting.assignments.count) filled")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                if activeMembers.isEmpty {
                    Text("No active members.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(activeMembers) { member in
                        AbsenteeRow(
                            member: member,
                            isAbsent: meeting.absentees.contains(where: { $0.persistentModelID == member.persistentModelID }),
                            isAssigned: assignedMemberIDs.contains(member.persistentModelID),
                            toggle: { toggleAbsent(member) }
                        )
                    }
                }
            } header: {
                Text("Attendance — mark absent members")
            } footer: {
                if !meeting.absentees.isEmpty {
                    Text("\(meeting.absentees.count) marked absent.")
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(meeting.theme.isEmpty ? "Meeting" : meeting.theme)
        .navigationSubtitle(meeting.date.formatted(date: .abbreviated, time: .omitted))
    }

    private var filledCount: Int {
        meeting.assignments.filter { $0.member != nil }.count
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

    @State private var showingTimes = false

    private var isIndented: Bool { role?.isIndented ?? false }
    private var defaultTiming: Timing { role?.timing ?? .zero }
    private var effectiveTiming: Timing { assignment.overrideTiming ?? defaultTiming }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label {
                    Text(assignment.displayLabel(role))
                        .foregroundStyle(isIndented ? .secondary : .primary)
                } icon: {
                    Image(systemName: role?.symbol ?? "questionmark.circle")
                        .foregroundStyle(.tint)
                }
                .padding(.leading, isIndented ? 16 : 0)

                Spacer()

                Picker("", selection: $assignment.member) {
                    Text("— Unassigned —").tag(Member?.none)
                    ForEach(membersForPicker) { member in
                        Text(member.name).tag(Member?.some(member))
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 220)
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
            .padding(.leading, isIndented ? 16 : 0)

            if showingTimes {
                TimingEditor(timing: Binding(
                    get: { assignment.overrideTiming ?? defaultTiming },
                    set: { assignment.setOverride($0) }
                ))
                .padding(.leading, isIndented ? 16 : 0)
            }
        }
        .padding(.vertical, 2)
    }

    /// Active members plus the currently-assigned member (in case they've gone
    /// inactive but are still on this meeting).
    private var membersForPicker: [Member] {
        guard let assigned = assignment.member,
              !members.contains(where: { $0.persistentModelID == assigned.persistentModelID }) else {
            return members
        }
        return (members + [assigned]).sorted { $0.name < $1.name }
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
