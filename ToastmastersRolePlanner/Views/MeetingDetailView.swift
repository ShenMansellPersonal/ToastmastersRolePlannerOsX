import SwiftUI
import SwiftData
import AppKit

struct MeetingDetailView: View {
    @Environment(\.modelContext) private var context
    @Bindable var meeting: Meeting

    @Query(sort: \Member.name) private var allMembers: [Member]
    @Query private var roles: [Role]
    @Query private var allAssignments: [RoleAssignment]

    private var rolesByKey: [String: Role] { Role.lookup(roles) }

    private var activeMembers: [Member] {
        allMembers.filter(\.isActive)
    }

    /// For the given role, the most relevant meeting date for each member: the
    /// current meeting's date if they're already assigned here, else the nearest
    /// future meeting, else the most recent past meeting.
    private func lastPerformedDates(roleKey: String) -> [PersistentIdentifier: Date] {
        var currentDates: [PersistentIdentifier: Date] = [:]
        var futureDates: [PersistentIdentifier: Date] = [:]
        var pastDates: [PersistentIdentifier: Date] = [:]
        for assignment in allAssignments {
            guard assignment.roleRaw == roleKey,
                  let member = assignment.member,
                  let otherMeeting = assignment.meeting
            else { continue }
            let id = member.persistentModelID
            let d = otherMeeting.date
            if otherMeeting.persistentModelID == meeting.persistentModelID {
                currentDates[id] = d
            } else if d > meeting.date {
                if futureDates[id] == nil || d < futureDates[id]! { futureDates[id] = d }
            } else {
                if pastDates[id] == nil || d > pastDates[id]! { pastDates[id] = d }
            }
        }
        var result = pastDates
        for (id, d) in futureDates { result[id] = d }
        for (id, d) in currentDates { result[id] = d }
        return result
    }

    /// Members assigned to at least one role in this meeting.
    private var assignedMemberIDs: Set<PersistentIdentifier> {
        Set(meeting.assignments.compactMap { $0.member?.persistentModelID })
    }

    /// Active members who aren't marked absent — the dropdown's candidates.
    private var assignableMembers: [Member] {
        let absent = Set(meeting.absentees.map(\.persistentModelID))
        return activeMembers.filter { !absent.contains($0.persistentModelID) }
    }

    /// Members who held a role in the meeting immediately before this one, plus
    /// whether such a meeting exists. Used to flag members who sat the last one out.
    private func previousMeetingAssignees() -> (assignees: Set<PersistentIdentifier>, existed: Bool) {
        let priorDate = allAssignments
            .compactMap { $0.meeting }
            .filter { $0.persistentModelID != meeting.persistentModelID && $0.date < meeting.date }
            .map(\.date)
            .max()
        guard let priorDate else { return ([], false) }
        var ids: Set<PersistentIdentifier> = []
        for assignment in allAssignments {
            guard let member = assignment.member,
                  let otherMeeting = assignment.meeting,
                  Calendar.current.isDate(otherMeeting.date, inSameDayAs: priorDate)
            else { continue }
            ids.insert(member.persistentModelID)
        }
        return (ids, true)
    }

    /// Active members who hold no role and aren't marked absent.
    private var membersWithoutRole: [Member] {
        let absent = Set(meeting.absentees.map(\.persistentModelID))
        return activeMembers.filter {
            !assignedMemberIDs.contains($0.persistentModelID) && !absent.contains($0.persistentModelID)
        }
    }

    /// A repeated *identical* slot (same role + instance, e.g. Toastmaster twice)
    /// is meant to be the same person, so it isn't a clash. Numbered copies
    /// (Speaker Intro #1 vs #2) are distinct slots and clash if shared.
    private func slotKey(_ assignment: RoleAssignment) -> String {
        "\(assignment.roleRaw)#\(assignment.instanceNumber)"
    }

    /// Key used for clash detection. Intro and Evaluation of the *same* speech
    /// collapse to one key, so the same person doing both isn't flagged.
    private func clashKey(_ assignment: RoleAssignment) -> String {
        if assignment.roleRaw == "speakerIntroduction" || assignment.roleRaw == "speakerEvaluation" {
            return "speakerPair#\(assignment.instanceNumber)"
        }
        return slotKey(assignment)
    }

    /// The Introduction↔Evaluation partner for a speaker slot, same instance.
    private func speakerPartner(of assignment: RoleAssignment) -> RoleAssignment? {
        let partnerKey: String
        switch assignment.roleRaw {
        case "speakerIntroduction": partnerKey = "speakerEvaluation"
        case "speakerEvaluation": partnerKey = "speakerIntroduction"
        default: return nil
        }
        return meeting.assignments.first { $0.roleRaw == partnerKey && $0.instanceNumber == assignment.instanceNumber }
    }

    /// Assigns a member to a role, mirroring the choice to any identical
    /// repeated slots (same role + instance, e.g. both Toastmaster slots).
    private func assign(_ member: Member?, to assignment: RoleAssignment) {
        let key = slotKey(assignment)
        for slot in meeting.assignments where slotKey(slot) == key {
            slot.assign(member)
        }
    }

    /// Members linked to more than one *distinct* role slot in this meeting.
    private var duplicateMemberIDs: Set<PersistentIdentifier> {
        var slotsByMember: [PersistentIdentifier: Set<String>] = [:]
        for assignment in meeting.assignments {
            guard let id = assignment.member?.persistentModelID else { continue }
            slotsByMember[id, default: []].insert(clashKey(assignment))
        }
        return Set(slotsByMember.filter { $0.value.count > 1 }.keys)
    }

    private func label(for assignment: RoleAssignment) -> String {
        assignment.displayLabel(rolesByKey[assignment.roleRaw])
    }

    /// Problems worth flagging on this meeting: a member in two roles, or a
    /// member who's both assigned a role and marked absent.
    private var warnings: [String] {
        var result: [String] = []

        // Same member across more than one distinct role slot. Repeated
        // identical slots (same role + instance) are expected to share a person.
        var info: [PersistentIdentifier: (name: String, keys: Set<String>, labels: [String])] = [:]
        for assignment in meeting.orderedAssignments {
            guard let member = assignment.member, rolesByKey[assignment.roleRaw]?.isUnmanned != true else { continue }
            var entry = info[member.persistentModelID] ?? (member.name, [], [])
            if entry.keys.insert(clashKey(assignment)).inserted {
                entry.labels.append(label(for: assignment))
            }
            info[member.persistentModelID] = entry
        }
        for entry in info.values where entry.keys.count > 1 {
            result.append("\(entry.name) is assigned to \(entry.keys.count) different roles: \(entry.labels.joined(separator: ", ")).")
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
        // First, where one half of a speaker pair (intro/eval) is already set
        // and the other is empty, copy the same person across.
        for assignment in meeting.assignments {
            guard assignment.isFilled,
                  let partner = speakerPartner(of: assignment),
                  !partner.isFilled
            else { continue }
            partner.member = assignment.member
            partner.memberName = assignment.memberName
        }

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
            // Fill this slot and any identical repeats (same role + instance)
            // with the same person.
            let key = slotKey(chosen)
            for slot in remaining where slotKey(slot) == key {
                slot.assign(member)
            }
            remaining.removeAll { slotKey($0) == key }

            // Default the same person to introduce and evaluate a speech.
            if let partner = speakerPartner(of: chosen), remaining.contains(where: { $0 === partner }) {
                partner.assign(member)
                remaining.removeAll { $0 === partner }
            }
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
                unassignedCard
                tableTopicsCard
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
        let previous = previousMeetingAssignees()
        return VStack(alignment: .leading, spacing: 8) {
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

                Button {
                    copyRoster()
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }
                .controlSize(.small)
                .keyboardShortcut("c", modifiers: .command)
                .help("Copy the roster (one name per line) to the clipboard (⌘C)")
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
                                members: assignableMembers,
                                lastPerformed: lastPerformedDates(roleKey: assignment.roleRaw),
                                referenceDate: meeting.date,
                                duplicateMemberIDs: duplicateMemberIDs,
                                assignedMemberIDs: assignedMemberIDs,
                                previousMeetingAssignees: previous.assignees,
                                hadPreviousMeeting: previous.existed,
                                assign: { assign($0, to: assignment) }
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

    private var unassignedCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Members without a role").font(.headline)
                Spacer()
                Text("\(membersWithoutRole.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            GroupBox {
                if membersWithoutRole.isEmpty {
                    Text("Every active member has a role or is absent.")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(6)
                } else {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(membersWithoutRole) { member in
                            Text(member.name)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(6)
                }
            }
        }
    }

    private var tableTopicsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Spoke at Table Topics").font(.headline)
                Spacer()
                if !meeting.tableTopicsSpeakers.isEmpty {
                    Text("\(meeting.tableTopicsSpeakers.count) ticked")
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
                            HStack {
                                Toggle(isOn: Binding(
                                    get: { meeting.tableTopicsSpeakers.contains { $0.persistentModelID == member.persistentModelID } },
                                    set: { _ in toggleTableTopics(member) }
                                )) {
                                    Text(member.name)
                                }
                                .toggleStyle(.checkbox)
                                Spacer()
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

    /// Copies the roster to the clipboard as tab-separated "role<TAB>name" lines
    /// in agenda order. Unmanned roles (Break, President's Close, Warm-Up) are
    /// excluded; unfilled manned roles are listed as "unassigned". A single-slot
    /// role that mistakenly appears more than once (e.g. Toastmaster, Sergeant at
    /// Arms) collapses to one line unless the assignee differs; multi-instance
    /// roles (speakers, intros, evaluators) are always listed individually.
    /// When one person both introduces and evaluates the same speaker, the two
    /// lines collapse into a single "Intro / Eval #x" line in place of the intro.
    /// Members with no role and apologies are flattened — one line each.
    private func copyRoster() {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "d MMMM'.' yyyy"   // e.g. "6 July. 2026"
        var lines: [String] = [dateFormatter.string(from: meeting.date)]
        var seen = Set<String>()   // roleRaw + name, to drop duplicate single-slot roles

        // When the same person introduces and evaluates a speaker (matched by
        // instance number), collapse the two lines into one "Intro / Eval #x" line
        // shown in place of the Introduction; the separate Evaluation line is dropped.
        let introKey = RoleType.speakerIntroduction.rawValue
        let evalKey = RoleType.speakerEvaluation.rawValue
        let evalNameByInstance = Dictionary(
            meeting.assignments
                .filter { $0.roleRaw == evalKey }
                .compactMap { a in a.assigneeName.map { (a.instanceNumber, $0) } },
            uniquingKeysWith: { first, _ in first }
        )
        let mergedInstances = Set(
            meeting.assignments
                .filter { $0.roleRaw == introKey }
                .filter { a in a.assigneeName != nil && evalNameByInstance[a.instanceNumber] == a.assigneeName }
                .map(\.instanceNumber)
        )

        for assignment in meeting.orderedAssignments {
            let role = rolesByKey[assignment.roleRaw]
            if role?.isUnmanned == true { continue }
            // Drop the Evaluation line when it's merged into the Introduction's.
            if assignment.roleRaw == evalKey, mergedInstances.contains(assignment.instanceNumber) { continue }
            let name = assignment.assigneeName ?? "unassigned"
            if role?.allowsMultiple != true,
               !seen.insert("\(assignment.roleRaw)\t\(name)").inserted { continue }
            if assignment.roleRaw == introKey, mergedInstances.contains(assignment.instanceNumber) {
                let suffix = assignment.instanceNumber > 0 ? " #\(assignment.instanceNumber)" : ""
                lines.append("Intro / Eval\(suffix)\t\(name)")
            } else {
                lines.append("\(assignment.displayLabel(role))\t\(name)")
            }
        }
        lines.append(contentsOf: membersWithoutRole.map { "No role\t\($0.name)" })
        lines.append(contentsOf: meeting.absentees.map { "Apologies\t\($0.name)" })

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(lines.joined(separator: "\n"), forType: .string)
    }

    private func toggleAbsent(_ member: Member) {
        // Reassign the whole array (reliably registers the change) and save, so
        // it persists to the store rather than only living in memory.
        var updated = meeting.absentees
        if let index = updated.firstIndex(where: { $0.persistentModelID == member.persistentModelID }) {
            updated.remove(at: index)
        } else {
            updated.append(member)
        }
        meeting.absentees = updated
        try? context.save()
    }

    private func toggleTableTopics(_ member: Member) {
        // Reassign the whole array (reliably registers the change) and save, so
        // it persists to the store rather than only living in memory.
        var updated = meeting.tableTopicsSpeakers
        if let index = updated.firstIndex(where: { $0.persistentModelID == member.persistentModelID }) {
            updated.remove(at: index)
        } else {
            updated.append(member)
        }
        meeting.tableTopicsSpeakers = updated
        try? context.save()
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
    /// Members already holding a role in this meeting.
    let assignedMemberIDs: Set<PersistentIdentifier>
    /// Members who had a role in the previous meeting.
    let previousMeetingAssignees: Set<PersistentIdentifier>
    /// Whether a previous meeting exists to compare against.
    let hadPreviousMeeting: Bool
    /// Assigns (or clears) the member, syncing identical repeated slots.
    let assign: (Member?) -> Void

    @State private var showingTimes = false

    /// Dropdown row decoration: strikethrough if the member already has a role
    /// in this meeting; a "!" if they sat out the previous meeting.
    @ViewBuilder
    private func menuLabel(for member: Member) -> some View {
        let text = memberLabel(member)
        if assignedMemberIDs.contains(member.persistentModelID) {
            Text(text).strikethrough()
        } else if hadPreviousMeeting && !previousMeetingAssignees.contains(member.persistentModelID) {
            Label(text, systemImage: "exclamationmark.circle")
        } else {
            Text(text)
        }
    }

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
                        Button("— Unassigned —") { assign(nil) }
                        Divider()
                        ForEach(sortedMembers) { member in
                            Button {
                                assign(member)
                            } label: {
                                menuLabel(for: member)
                            }
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

    /// "Name · 14d ago" / "Name · now" / "Name · in 7d" / "Name · never"
    private func memberLabel(_ member: Member) -> String {
        let suffix: String
        if let last = lastPerformed[member.persistentModelID] {
            let calendar = Calendar.current
            let days = calendar.dateComponents(
                [.day],
                from: calendar.startOfDay(for: last),
                to: calendar.startOfDay(for: referenceDate)
            ).day ?? 0
            if days == 0 { suffix = "now" }
            else if days < 0 { suffix = "in \(-days)d" }
            else { suffix = "\(days)d ago" }
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
