import SwiftUI
import SwiftData

@main
struct ToastmastersRolePlannerApp: App {
    /// True when the process is hosting unit tests. In that case the app must
    /// not create its own `ModelContainer`, so it doesn't collide with the
    /// in-memory container each test creates.
    private static let isRunningTests = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil

    /// Created lazily on first access, so it's never built during tests.
    static let sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Member.self,
            MeetingTemplate.self,
            TemplateSlot.self,
            Meeting.self,
            RoleAssignment.self,
            Role.self,
            RoleDefault.self
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            // The on-disk store is incompatible (e.g. an old schema). As a last
            // resort, discard it and start fresh rather than crash-looping.
            if let url = configuration.url as URL?, FileManager.default.fileExists(atPath: url.path) {
                try? FileManager.default.removeItem(at: url)
                if let retry = try? ModelContainer(for: schema, configurations: [configuration]) {
                    return retry
                }
            }
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            if Self.isRunningTests {
                EmptyView()
            } else {
                ContentView()
                    .frame(minWidth: 820, minHeight: 520)
                    .modelContainer(Self.sharedModelContainer)
            }
        }
        .commands {
            SidebarCommands()
            ImportExportCommands()
            TemplateCommands()
        }
    }
}
