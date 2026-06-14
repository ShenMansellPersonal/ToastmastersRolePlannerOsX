import SwiftUI
import SwiftData

struct ContentView: View {
    enum Section: String, CaseIterable, Identifiable {
        case meetings = "Meetings"
        case templates = "Templates"
        case members = "Members"
        case roles = "Roles"
        case reports = "Reports"
        case memberDetail = "Member Detail"

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .meetings: "calendar"
            case .templates: "list.bullet.rectangle"
            case .members: "person.2"
            case .roles: "person.text.rectangle"
            case .reports: "chart.bar.doc.horizontal"
            case .memberDetail: "person.badge.clock"
            }
        }
    }

    @Environment(\.modelContext) private var context
    @State private var selection: Section? = .meetings
    @State private var selectedMeeting: Meeting?
    @State private var selectedTemplate: MeetingTemplate?
    @State private var selectedRole: Role?
    @State private var reportStart = Calendar.current.date(byAdding: .year, value: -1, to: Date()) ?? Date()
    @State private var reportEnd = Date()

    private var section: Section { selection ?? .meetings }

    var body: some View {
        NavigationSplitView {
            List(Section.allCases, selection: $selection) { section in
                Label(section.rawValue, systemImage: section.icon)
                    .tag(section)
            }
            .navigationSplitViewColumnWidth(min: 170, ideal: 190, max: 240)
            .navigationTitle("Toastmasters")
        } content: {
            sectionList
                .navigationSplitViewColumnWidth(min: 240, ideal: 280)
        } detail: {
            sectionDetail
        }
        .onAppear {
            Role.ensureSeeded(in: context)
            MeetingTemplate.ensureDefaultSeeded(in: context)
        }
    }

    @ViewBuilder private var sectionList: some View {
        switch section {
        case .meetings: MeetingsListView(selection: $selectedMeeting)
        case .templates: TemplatesListView(selection: $selectedTemplate)
        case .members: MembersView()
        case .roles: RolesListView(selection: $selectedRole)
        case .reports: ReportControls(start: $reportStart, end: $reportEnd)
        case .memberDetail: MemberDetailControls()
        }
    }

    @ViewBuilder private var sectionDetail: some View {
        switch section {
        case .meetings:
            if let selectedMeeting {
                MeetingDetailView(meeting: selectedMeeting)
                    .id(selectedMeeting.persistentModelID)
            } else {
                ContentUnavailableView("Select a Meeting", systemImage: "calendar")
            }
        case .templates:
            if let selectedTemplate {
                TemplateEditor(template: selectedTemplate)
                    .id(selectedTemplate.persistentModelID)
            } else {
                ContentUnavailableView("Select a Template", systemImage: "list.bullet.rectangle")
            }
        case .roles:
            if let selectedRole {
                RoleEditor(role: selectedRole)
                    .id(selectedRole.persistentModelID)
            } else {
                ContentUnavailableView("Select a Role", systemImage: "person.text.rectangle")
            }
        case .members:
            ContentUnavailableView(
                "Members",
                systemImage: "person.2",
                description: Text("Add, rename, and manage club members in the list.")
            )
        case .reports:
            ReportPreview(start: reportStart, end: reportEnd)
        case .memberDetail:
            MemberDetailPreview()
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(PreviewData.container)
}
