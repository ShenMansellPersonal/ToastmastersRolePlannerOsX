import SwiftUI
import SwiftData

@main
struct ToastmastersRolePlannerApp: App {
    let sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Member.self,
            MeetingTemplate.self,
            TemplateSlot.self,
            Meeting.self,
            RoleAssignment.self
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 820, minHeight: 520)
        }
        .modelContainer(sharedModelContainer)
        .commands {
            SidebarCommands()
        }
    }
}
