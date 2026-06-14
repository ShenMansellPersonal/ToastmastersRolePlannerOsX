import SwiftUI
import SwiftData

struct MembersView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Member.name) private var members: [Member]

    @State private var newName = ""
    @State private var showInactive = true

    private var visibleMembers: [Member] {
        showInactive ? members : members.filter(\.isActive)
    }

    var body: some View {
        List {
            Section {
                HStack {
                    TextField("Add a member…", text: $newName)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(addMember)
                    Button("Add", action: addMember)
                        .disabled(trimmedName.isEmpty)
                }
            }

            Section {
                if visibleMembers.isEmpty {
                    Text("No members yet.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(visibleMembers) { member in
                        MemberRow(member: member)
                    }
                    .onDelete(perform: deleteMembers)
                }
            } header: {
                HStack {
                    Text("\(members.filter(\.isActive).count) active · \(members.count) total")
                    Spacer()
                    Toggle("Show inactive", isOn: $showInactive)
                        .toggleStyle(.checkbox)
                        .font(.caption)
                }
            }
        }
        .navigationTitle("Members")
    }

    private var trimmedName: String {
        newName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func addMember() {
        guard !trimmedName.isEmpty else { return }
        context.insert(Member(name: trimmedName))
        newName = ""
    }

    private func deleteMembers(at offsets: IndexSet) {
        for index in offsets {
            context.delete(visibleMembers[index])
        }
    }
}

private struct MemberRow: View {
    @Bindable var member: Member

    var body: some View {
        HStack {
            Toggle("Active", isOn: $member.isActive)
                .toggleStyle(.checkbox)
                .labelsHidden()
                .help(member.isActive ? "Active member" : "Inactive member")

            TextField("Name", text: $member.name)
                .textFieldStyle(.plain)
                .foregroundStyle(member.isActive ? .primary : .secondary)

            Spacer()

            if !member.isActive {
                Text("Inactive")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

#Preview {
    MembersView()
        .modelContainer(PreviewData.container)
}
