import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct TemplatesListView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \MeetingTemplate.name) private var templates: [MeetingTemplate]

    @Binding var selection: MeetingTemplate?

    @State private var showingExporter = false
    @State private var showingImporter = false
    @State private var exportDocument = TemplatesJSONDocument(data: Data())
    @State private var resultMessage: String?

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
        .focusedSceneValue(\.importExport, ImportExportActions(
            exportTitle: "Export Templates to JSON…",
            importTitle: "Import Templates from JSON…",
            exportAction: { startExport() },
            importAction: { showingImporter = true }
        ))
        .focusedSceneValue(\.templateMenu, selection.map { template in
            TemplateMenuActions(duplicate: { duplicate(template) })
        })
        .fileExporter(
            isPresented: $showingExporter,
            document: exportDocument,
            contentType: .json,
            defaultFilename: "Meeting Templates"
        ) { result in
            if case .failure(let error) = result {
                resultMessage = "Export failed: \(error.localizedDescription)"
            }
        }
        .fileImporter(
            isPresented: $showingImporter,
            allowedContentTypes: [.json]
        ) { result in
            handleImport(result)
        }
        .alert("Templates", isPresented: Binding(get: { resultMessage != nil }, set: { if !$0 { resultMessage = nil } })) {
            Button("OK", role: .cancel) { resultMessage = nil }
        } message: {
            Text(resultMessage ?? "")
        }
    }

    private func addTemplate() {
        let template = MeetingTemplate(name: "New Template")
        context.insert(template)
        selection = template
    }

    private func duplicate(_ template: MeetingTemplate) {
        let copy = MeetingTemplate(name: template.name + " (Copy)", details: template.details)
        context.insert(copy)
        copy.slots = template.orderedSlots.map {
            TemplateSlot(roleKey: $0.roleRaw, order: $0.order, instanceNumber: $0.instanceNumber, customLabel: $0.customLabel)
        }
        selection = copy
    }

    private func startExport() {
        do {
            exportDocument = TemplatesJSONDocument(data: try TemplateIO.export(templates))
            showingExporter = true
        } catch {
            resultMessage = "Export failed: \(error.localizedDescription)"
        }
    }

    private func handleImport(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            let needsScope = url.startAccessingSecurityScopedResource()
            defer { if needsScope { url.stopAccessingSecurityScopedResource() } }
            do {
                let data = try Data(contentsOf: url)
                let outcome = try TemplateIO.importing(data, into: context, existing: templates)
                resultMessage = "Imported \(outcome.inserted) new, updated \(outcome.updated)."
                if let first = outcome.templates.first { selection = first }
            } catch {
                resultMessage = "Import failed: \(error.localizedDescription)"
            }
        case .failure(let error):
            resultMessage = "Import failed: \(error.localizedDescription)"
        }
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
    @Environment(\.modelContext) private var context
    @Bindable var template: MeetingTemplate
    @Query(sort: \Role.sortOrder) private var roles: [Role]

    private var rolesByKey: [String: Role] { Role.lookup(roles) }

    /// Sum of each slot's role green / red signal times (the estimated range).
    private var totalGreen: Int {
        template.slots.reduce(0) { $0 + (rolesByKey[$1.roleRaw]?.green ?? 0) }
    }
    private var totalRed: Int {
        template.slots.reduce(0) { $0 + (rolesByKey[$1.roleRaw]?.red ?? 0) }
    }

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
                            SlotRow(slot: slot, role: rolesByKey[slot.roleRaw]) {
                                removeSlot(slot)
                            }
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

            if !template.slots.isEmpty {
                Section {
                    LabeledContent("Estimated length", value: "\(totalGreen.asMMSS) – \(totalRed.asMMSS)")
                } footer: {
                    Text("Sum of every role's green-to-red signal times (minutes:seconds).")
                }
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
        offsets.map { ordered[$0] }.forEach(removeSlot)
    }

    private func removeSlot(_ slot: TemplateSlot) {
        template.slots.removeAll { $0 === slot }
        context.delete(slot)
        // Re-pack order values.
        for (index, remaining) in template.orderedSlots.enumerated() {
            remaining.order = index
        }
    }
}

private struct SlotRow: View {
    @Bindable var slot: TemplateSlot
    let role: Role?
    let onRemove: () -> Void

    var body: some View {
        HStack {
            Image(systemName: role?.symbol ?? "questionmark.circle")
                .foregroundStyle(.tint)
                .frame(width: 18)
            TextField(role?.label(instance: slot.instanceNumber) ?? "(deleted role)", text: $slot.customLabel)
                .textFieldStyle(.plain)
            Button(role: .destructive, action: onRemove) {
                Image(systemName: "minus.circle.fill")
                    .foregroundStyle(.red)
            }
            .buttonStyle(.borderless)
            .help("Remove this role from the template")
        }
    }
}

#Preview {
    NavigationStack {
        TemplatesListView(selection: .constant(nil))
    }
    .modelContainer(PreviewData.container)
}
