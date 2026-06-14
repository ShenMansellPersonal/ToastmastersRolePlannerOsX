import SwiftUI
import SwiftData

struct TemplatesView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \MeetingTemplate.name) private var templates: [MeetingTemplate]

    @State private var selection: MeetingTemplate?

    var body: some View {
        NavigationSplitView {
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
            .navigationSplitViewColumnWidth(min: 200, ideal: 240)
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
        } detail: {
            if let selection {
                TemplateEditor(template: selection)
                    .id(selection.persistentModelID)
            } else {
                ContentUnavailableView("Select a Template", systemImage: "sidebar.left")
            }
        }
        .navigationTitle("Templates")
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

private struct TemplateEditor: View {
    @Bindable var template: MeetingTemplate

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
                            SlotRow(slot: slot)
                        }
                        .onMove(perform: moveSlots)
                        .onDelete(perform: deleteSlots)
                    }
                    .frame(minHeight: 220)
                }
            } header: {
                Text("Agenda (\(template.slots.count) roles)")
            } footer: {
                HStack {
                    Menu {
                        ForEach(RoleType.singleAddable) { role in
                            Button(role.title) { addRole(role) }
                        }
                    } label: {
                        Label("Add Role", systemImage: "plus")
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()

                    Button {
                        addSpeakerBlock()
                    } label: {
                        Label("Add Speaker (+ Intro & Evaluation)", systemImage: "mic.badge.plus")
                    }
                }
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

    private func addRole(_ role: RoleType) {
        let instance: Int
        if role.allowsMultiple {
            let existing = template.slots.filter { $0.role == role }.map(\.instanceNumber)
            instance = (existing.max() ?? 0) + 1
        } else {
            instance = 0
        }
        template.slots.append(TemplateSlot(role: role, order: nextOrder, instanceNumber: instance))
    }

    private func addSpeakerBlock() {
        let existingSpeakers = template.slots
            .filter { $0.role == .speaker }
            .map(\.instanceNumber)
        let instance = (existingSpeakers.max() ?? 0) + 1
        var order = nextOrder
        template.slots.append(TemplateSlot(role: .speaker, order: order, instanceNumber: instance))
        order += 1
        template.slots.append(TemplateSlot(role: .speakerIntroduction, order: order, instanceNumber: instance))
        order += 1
        template.slots.append(TemplateSlot(role: .speakerEvaluation, order: order, instanceNumber: instance))
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
    let slot: TemplateSlot

    var body: some View {
        Label {
            Text(slot.label)
                .foregroundStyle(slot.role.isIndented ? .secondary : .primary)
        } icon: {
            Image(systemName: slot.role.symbol)
                .foregroundStyle(.tint)
        }
        .padding(.leading, slot.role.isIndented ? 20 : 0)
    }
}

#Preview {
    TemplatesView()
        .modelContainer(PreviewData.container)
}
