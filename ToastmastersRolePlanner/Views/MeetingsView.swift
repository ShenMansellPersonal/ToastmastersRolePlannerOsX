import SwiftUI
import SwiftData

struct MeetingsListView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Meeting.date, order: .reverse) private var meetings: [Meeting]
    @Query private var templates: [MeetingTemplate]

    @Binding var selection: Meeting?
    @State private var showingNewMeeting = false

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
