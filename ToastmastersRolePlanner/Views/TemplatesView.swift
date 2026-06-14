import SwiftUI
import SwiftData

struct TemplatesListView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \MeetingTemplate.name) private var templates: [MeetingTemplate]

    @Binding var selection: MeetingTemplate?

    var body: some View {
        List(selection: $selection) {
            ForEach(templates) { template in
                VStack(alignment: .leading, spacing: 2) {
                    Text(template.name.isEmpty ? "Untitled Template" : template.name)
                    Text("\(template.slots.count) roles")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .tag(template)
            }
            .onDelete(perform: deleteTemplates)
        }
        .navigationTitle("Templates")
        .toolbar {
            ToolbarItem {
                Button(action: addTemplate) {
                    Label("New Template", systemImage: "plus")
                }
            }
        }
        .overlay {
            if templates.isEmpty {
                ContentUnavailableView(
                    "No Templates",
                    systemImage: "list.bullet.rectangle",
                    description: Text("Create a template to define the agenda for a meeting.")
                )
            }
        }
    }

    private func addTemplate() {
        let template = MeetingTemplate(name: "New Template")
        context.insert(template)
        selection = template
    }

    private func deleteTemplates(at offsets: IndexSet) {
        for index in offsets {
            let template = templates[index]
            if template == selection { selection = nil }
            context.delete(template)
        }
    }
}

// MARK: - Editor

struct TemplateEditor: View {
    @Bindable var template: MeetingTemplate
    @Query(sort: \Role.sortOrder) private var roles: [Role]

    private var rolesByKey: [String: Role] { Role.lookup(roles) }

    var body: some View {
        Form {
            Section("Details") {
                TextField("Template name", text: $template.name)
                TextField("Notes (optional)", text: $template.details, axis: .vertical)
                    .lineLimit(1...4)
            }

            Section {
                if template.slots.isEmpty {
                    Text("No roles yet. Use the buttons below to build the agenda.")
                        .foregroundStyle(.secondary)
                } else {
                    List {
                        ForEach(template.orderedSlots) { slot in
                            SlotRow(slot: slot, role: rolesByKey[slot.roleRaw])
                        }
                        .onMove(perform: moveSlots)
                        .onDelete(perform: deleteSlots)
                    }
                    .frame(minHeight: 220)
                }
            } header: {
                Text("Agenda (\(template.slots.count) roles)")
            } footer: {
                Menu {
                    ForEach(roles) { role in
                        Button {
                            addRole(role)
                        } label: {
                            Label(role.name, systemImage: role.symbol)
                        }
                    }
                } label: {
                    Label("Add Role", systemImage: "plus")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .padding(.top, 4)
            }
        }
        .formStyle(.grouped)
        .navigationTitle(template.name.isEmpty ? "Template" : template.name)
    }

    // MARK: Editing

    private var nextOrder: Int {
        (template.slots.map(\.order).max() ?? -1) + 1
    }

    private func addRole(_ role: Role) {
        let instance: Int
        if role.allowsMultiple {
            let existing = template.slots.filter { $0.roleRaw == role.key }.map(\.instanceNumber)
            instance = (existing.max() ?? 0) + 1
        } else {
            instance = 0
        }
        template.slots.append(TemplateSlot(roleKey: role.key, order: nextOrder, instanceNumber: instance))
    }

    private func moveSlots(from source: IndexSet, to destination: Int) {
        var ordered = template.orderedSlots
        ordered.move(fromOffsets: source, toOffset: destination)
        for (index, slot) in ordered.enumerated() {
            slot.order = index
        }
    }

    private func deleteSlots(at offsets: IndexSet) {
        let ordered = template.orderedSlots
        for index in offsets {
            template.slots.removeAll { $0 == ordered[index] }
        }
        // Re-pack order values.
        for (index, slot) in template.orderedSlots.enumerated() {
            slot.order = index
        }
    }
}

private struct SlotRow: View {
    @Bindable var slot: TemplateSlot
    let role: Role?

    private var isIndented: Bool { role?.isIndented ?? false }

    var body: some View {
        HStack {
            Image(systemName: role?.symbol ?? "questionmark.circle")
                .foregroundStyle(.tint)
                .frame(width: 18)
            TextField(role?.label(instance: slot.instanceNumber) ?? "(deleted role)", text: $slot.customLabel)
                .textFieldStyle(.plain)
                .foregroundStyle(isIndented ? .secondary : .primary)
        }
        .padding(.leading, isIndented ? 20 : 0)
    }
}

#Preview {
    NavigationStack {
        TemplatesListView(selection: .constant(nil))
    }
    .modelContainer(PreviewData.container)
}
