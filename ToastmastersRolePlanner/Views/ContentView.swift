import SwiftUI
import SwiftData

struct ContentView: View {
    enum Section: String, CaseIterable, Identifiable {
        case meetings = "Meetings"
        case templates = "Templates"
        case members = "Members"
        case roles = "Roles"

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .meetings: "calendar"
            case .templates: "list.bullet.rectangle"
            case .members: "person.2"
            case .roles: "person.text.rectangle"
            }
        }
    }

    @Environment(\.modelContext) private var context
    @State private var selection: Section? = .meetings

    var body: some View {
        NavigationSplitView {
            List(Section.allCases, selection: $selection) { section in
                Label(section.rawValue, systemImage: section.icon)
                    .tag(section)
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 260)
            .navigationTitle("Toastmasters")
        } detail: {
            switch selection ?? .meetings {
            case .meetings: MeetingsView()
            case .templates: TemplatesView()
            case .members: MembersView()
            case .roles: RolesView()
            }
        }
        .onAppear {
            Role.ensureSeeded(in: context)
            MeetingTemplate.ensureDefaultSeeded(in: context)
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(PreviewData.container)
}
