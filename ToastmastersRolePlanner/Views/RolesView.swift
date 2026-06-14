import SwiftUI
import SwiftData

/// View, add, edit, and delete the club's role catalogue. Each role carries its
/// default green / yellow / red signal times (overridable per meeting).
struct RolesListView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Role.sortOrder) private var roles: [Role]

    @Binding var selection: Role?

    var body: some View {
        List(selection: $selection) {
            ForEach(roles) { role in
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(role.name.isEmpty ? "Untitled Role" : role.name)
                        TimingSummary(timing: role.timing, isCustom: false)
                    }
                } icon: {
                    Image(systemName: role.symbol)
                        .foregroundStyle(.tint)
                }
                .tag(role)
            }
            .onDelete(perform: deleteRoles)
        }
        .navigationTitle("Roles")
        .toolbar {
            ToolbarItem {
                Button(action: addRole) {
                    Label("New Role", systemImage: "plus")
                }
            }
        }
        .onAppear { Role.ensureSeeded(in: context) }
    }

    private func addRole() {
        let nextOrder = (roles.map(\.sortOrder).max() ?? -1) + 1
        let role = Role(
            key: Role.newKey(),
            name: "New Role",
            symbol: "person",
            timing: Timing(green: 60, yellow: 90, red: 120),
            sortOrder: nextOrder
        )
        context.insert(role)
        selection = role
    }

    private func deleteRoles(at offsets: IndexSet) {
        for index in offsets {
            let role = roles[index]
            if role == selection { selection = nil }
            context.delete(role)
        }
    }
}

// MARK: - Editor

struct RoleEditor: View {
    @Bindable var role: Role

    /// A small palette of suggested SF Symbols for quick selection.
    private let suggestedSymbols = [
        "person", "person.wave.2", "shield", "flame", "textformat.abc",
        "hand.raised", "mic", "arrow.turn.down.right", "bubble.left.and.bubble.right",
        "checkmark.bubble", "cup.and.saucer", "list.clipboard", "star.bubble",
        "stopwatch", "flag.checkered", "clock", "megaphone", "book"
    ]

    var body: some View {
        Form {
            Section("Role") {
                TextField("Name", text: $role.name)

                LabeledContent("Icon") {
                    HStack {
                        Image(systemName: role.symbol.isEmpty ? "questionmark" : role.symbol)
                            .foregroundStyle(.tint)
                            .frame(width: 22)
                        TextField("SF Symbol name", text: $role.symbol)
                    }
                }

                Picker("Quick icon", selection: $role.symbol) {
                    ForEach(suggestedSymbols, id: \.self) { symbol in
                        Image(systemName: symbol).tag(symbol)
                    }
                }
                .pickerStyle(.menu)
            }

            Section {
                Toggle("Can appear multiple times per meeting", isOn: $role.allowsMultiple)
                Toggle("Unmanned role (no person assigned)", isOn: $role.isUnmanned)
                Toggle("Show in roles report", isOn: $role.showInRolesReport)
            } footer: {
                Text("“Multiple” numbers the role as #1, #2… on an agenda. “Unmanned” roles (e.g. Break) appear on the agenda without a member assigned.")
            }

            Section("Default times") {
                TimingEditor(timing: Binding(
                    get: { role.timing },
                    set: { role.timing = $0 }
                ))
            }
        }
        .formStyle(.grouped)
        .navigationTitle(role.name.isEmpty ? "Role" : role.name)
    }
}

#Preview {
    NavigationStack {
        RolesListView(selection: .constant(nil))
    }
    .modelContainer(PreviewData.container)
}
