import SwiftUI
import SwiftData

/// Edits the default green / yellow / red signal times for every role.
/// These defaults are applied to new meetings and can be overridden per meeting.
struct RoleTimesView: View {
    @Environment(\.modelContext) private var context
    @Query private var defaults: [RoleDefault]

    var body: some View {
        Form {
            Section {
                Text("Default signal times for each role. New meetings start from these; you can override them per meeting from the meeting's roles list.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            ForEach(orderedDefaults) { roleDefault in
                Section {
                    TimingEditor(timing: Binding(
                        get: { roleDefault.timing },
                        set: { roleDefault.timing = $0 }
                    ))
                    Button("Reset to standard") {
                        roleDefault.timing = roleDefault.role.defaultTiming
                    }
                    .disabled(roleDefault.timing == roleDefault.role.defaultTiming)
                } header: {
                    Label(roleDefault.role.title, systemImage: roleDefault.role.symbol)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Role Times")
        .onAppear { RoleDefault.ensureSeeded(in: context) }
    }

    /// Defaults ordered to match the declaration order of `RoleType`.
    private var orderedDefaults: [RoleDefault] {
        let order = Dictionary(
            uniqueKeysWithValues: RoleType.allCases.enumerated().map { ($1.rawValue, $0) }
        )
        return defaults.sorted { (order[$0.roleRaw] ?? .max) < (order[$1.roleRaw] ?? .max) }
    }
}

#Preview {
    NavigationStack {
        RoleTimesView()
    }
    .modelContainer(PreviewData.container)
}
