import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct MembersView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Member.name) private var members: [Member]

    @State private var newName = ""
    @State private var showInactive = true

    @State private var showingExporter = false
    @State private var showingImporter = false
    @State private var exportDocument = MembersCSVDocument(text: "")
    @State private var resultMessage: String?

    private var visibleMembers: [Member] {
        showInactive ? members : members.filter(\.isActive)
    }

    var body: some View {
        List {
            Section {
                HStack {
                    TextField("Add a member…", text: $newName)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(addMember)
                    Button("Add", action: addMember)
                        .disabled(trimmedName.isEmpty)
                }
            }

            Section {
                if visibleMembers.isEmpty {
                    Text("No members yet.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(visibleMembers) { member in
                        MemberRow(member: member)
                    }
                    .onDelete(perform: deleteMembers)
                }
            } header: {
                HStack {
                    Text("\(members.filter(\.isActive).count) active · \(members.count) total")
                    Spacer()
                    Toggle("Show inactive", isOn: $showInactive)
                        .toggleStyle(.checkbox)
                        .font(.caption)
                }
            }
        }
        .navigationTitle("Members")
        .toolbar {
            ToolbarItem {
                Menu {
                    Button {
                        exportDocument = MembersCSVDocument(text: MemberCSV.export(members))
                        showingExporter = true
                    } label: {
                        Label("Export to CSV…", systemImage: "square.and.arrow.up")
                    }
                    .disabled(members.isEmpty)

                    Button {
                        showingImporter = true
                    } label: {
                        Label("Import from CSV…", systemImage: "square.and.arrow.down")
                    }
                } label: {
                    Label("Import / Export", systemImage: "arrow.up.arrow.down")
                }
            }
        }
        .fileExporter(
            isPresented: $showingExporter,
            document: exportDocument,
            contentType: .commaSeparatedText,
            defaultFilename: "Members"
        ) { result in
            if case .failure(let error) = result {
                resultMessage = "Export failed: \(error.localizedDescription)"
            }
        }
        .fileImporter(
            isPresented: $showingImporter,
            allowedContentTypes: [.commaSeparatedText, .plainText, .text]
        ) { result in
            handleImport(result)
        }
        .alert("Members", isPresented: Binding(get: { resultMessage != nil }, set: { if !$0 { resultMessage = nil } })) {
            Button("OK", role: .cancel) { resultMessage = nil }
        } message: {
            Text(resultMessage ?? "")
        }
    }

    private func handleImport(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            let needsScope = url.startAccessingSecurityScopedResource()
            defer { if needsScope { url.stopAccessingSecurityScopedResource() } }
            do {
                let data = try Data(contentsOf: url)
                let text = String(decoding: data, as: UTF8.self)
                let counts = MemberCSV.importing(text, into: context, existing: members)
                resultMessage = "Imported \(counts.inserted) new member\(counts.inserted == 1 ? "" : "s"), updated \(counts.updated)."
            } catch {
                resultMessage = "Import failed: \(error.localizedDescription)"
            }
        case .failure(let error):
            resultMessage = "Import failed: \(error.localizedDescription)"
        }
    }

    private var trimmedName: String {
        newName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func addMember() {
        guard !trimmedName.isEmpty else { return }
        context.insert(Member(name: trimmedName))
        newName = ""
    }

    private func deleteMembers(at offsets: IndexSet) {
        for index in offsets {
            context.delete(visibleMembers[index])
        }
    }
}

private struct MemberRow: View {
    @Bindable var member: Member

    var body: some View {
        HStack {
            Toggle("Active", isOn: $member.isActive)
                .toggleStyle(.checkbox)
                .labelsHidden()
                .help(member.isActive ? "Active member" : "Inactive member")

            TextField("Name", text: $member.name)
                .textFieldStyle(.plain)
                .foregroundStyle(member.isActive ? .primary : .secondary)

            Spacer()

            if !member.isActive {
                Text("Inactive")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

#Preview {
    MembersView()
        .modelContainer(PreviewData.container)
}
