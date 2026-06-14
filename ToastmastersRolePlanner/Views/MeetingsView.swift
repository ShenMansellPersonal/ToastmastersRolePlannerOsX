import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct MeetingsListView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Meeting.date, order: .reverse) private var meetings: [Meeting]
    @Query private var templates: [MeetingTemplate]
    @Query private var members: [Member]
    @Query private var roles: [Role]

    @Binding var selection: Meeting?
    @State private var showingNewMeeting = false

    @State private var showingExporter = false
    @State private var showingImporter = false
    @State private var exportDocument = MeetingsJSONDocument(data: Data())
    @State private var resultMessage: String?

    var body: some View {
        List(selection: $selection) {
            ForEach(meetings) { meeting in
                VStack(alignment: .leading, spacing: 2) {
                    Text(meeting.date, format: .dateTime.weekday().day().month().year())
                        .fontWeight(.medium)
                    Text(meeting.theme.isEmpty ? meeting.templateName : meeting.theme)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .tag(meeting)
            }
            .onDelete(perform: deleteMeetings)
        }
        .navigationTitle("Meetings")
        .toolbar {
            ToolbarItem {
                Menu {
                    Button {
                        startExport()
                    } label: {
                        Label("Export to JSON…", systemImage: "square.and.arrow.up")
                    }
                    .disabled(meetings.isEmpty)

                    Button {
                        showingImporter = true
                    } label: {
                        Label("Import from JSON…", systemImage: "square.and.arrow.down")
                    }
                } label: {
                    Label("Import / Export", systemImage: "arrow.up.arrow.down")
                }
            }
            ToolbarItem {
                Button {
                    showingNewMeeting = true
                } label: {
                    Label("New Meeting", systemImage: "plus")
                }
                .disabled(templates.isEmpty)
                .help(templates.isEmpty ? "Create a template first" : "New meeting")
            }
        }
        .overlay {
            if meetings.isEmpty {
                ContentUnavailableView {
                    Label("No Meetings", systemImage: "calendar")
                } description: {
                    Text(templates.isEmpty
                         ? "Create a template first, then schedule a meeting."
                         : "Schedule a meeting to assign roles.")
                }
            }
        }
        .sheet(isPresented: $showingNewMeeting) {
            NewMeetingSheet { newMeeting in
                selection = newMeeting
            }
        }
        .fileExporter(
            isPresented: $showingExporter,
            document: exportDocument,
            contentType: .json,
            defaultFilename: "Meetings"
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
        .alert("Meetings", isPresented: Binding(get: { resultMessage != nil }, set: { if !$0 { resultMessage = nil } })) {
            Button("OK", role: .cancel) { resultMessage = nil }
        } message: {
            Text(resultMessage ?? "")
        }
    }

    private func startExport() {
        do {
            let data = try MeetingIO.export(meetings, rolesByKey: Role.lookup(roles))
            exportDocument = MeetingsJSONDocument(data: data)
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
                let count = try MeetingIO.importing(data, into: context, members: members)
                resultMessage = "Imported \(count) meeting\(count == 1 ? "" : "s")."
            } catch {
                resultMessage = "Import failed: \(error.localizedDescription)"
            }
        case .failure(let error):
            resultMessage = "Import failed: \(error.localizedDescription)"
        }
    }

    private func deleteMeetings(at offsets: IndexSet) {
        for index in offsets {
            let meeting = meetings[index]
            if meeting == selection { selection = nil }
            context.delete(meeting)
        }
    }
}

// MARK: - New meeting sheet

private struct NewMeetingSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \MeetingTemplate.name) private var templates: [MeetingTemplate]

    @State private var date = Date()
    @State private var theme = ""
    @State private var selectedTemplate: MeetingTemplate?

    var onCreate: (Meeting) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("New Meeting")
                .font(.title2.bold())
                .padding()

            Divider()

            Form {
                DatePicker("Date", selection: $date, displayedComponents: [.date])
                TextField("Theme (optional)", text: $theme)
                Picker("Template", selection: $selectedTemplate) {
                    Text("Choose…").tag(MeetingTemplate?.none)
                    ForEach(templates) { template in
                        Text(template.name).tag(MeetingTemplate?.some(template))
                    }
                }
            }
            .formStyle(.grouped)

            Divider()

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                Button("Create") { create() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(selectedTemplate == nil)
            }
            .padding()
        }
        .frame(width: 420)
        .onAppear {
            if selectedTemplate == nil { selectedTemplate = templates.first }
        }
    }

    private func create() {
        guard let template = selectedTemplate else { return }
        let meeting = Meeting(date: date, theme: theme)
        meeting.applyTemplate(template)
        context.insert(meeting)
        onCreate(meeting)
        dismiss()
    }
}

#Preview {
    NavigationStack {
        MeetingsListView(selection: .constant(nil))
    }
    .modelContainer(PreviewData.container)
}
