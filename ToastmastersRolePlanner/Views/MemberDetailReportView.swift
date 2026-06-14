import SwiftUI
import SwiftData
import CoreGraphics
import UniformTypeIdentifiers

// MARK: - Controls (content column)

struct MemberDetailControls: View {
    @Query private var members: [Member]
    @Query private var roles: [Role]
    @Query private var meetings: [Meeting]

    @State private var showingExporter = false
    @State private var pdfDocument = ReportPDFDocument(data: Data())
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Section {
                Button {
                    exportPDF()
                } label: {
                    Label("Export PDF…", systemImage: "square.and.arrow.up")
                }
            } footer: {
                Text("For each current member, the number of days since they last performed each role (excluding unmanned roles).")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Member Detail")
        .fileExporter(
            isPresented: $showingExporter,
            document: pdfDocument,
            contentType: .pdf,
            defaultFilename: "Member Role Detail"
        ) { result in
            if case .failure(let error) = result {
                errorMessage = error.localizedDescription
            }
        }
        .alert("Export failed", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    @MainActor
    private func exportPDF() {
        let report = MemberRoleDetailReport.build(members: members, roles: roles, meetings: meetings, asOf: Date())
        pdfDocument = ReportPDFDocument(data: MemberDetailPDF.render(report))
        showingExporter = true
    }
}

// MARK: - Preview (detail column)

struct MemberDetailPreview: View {
    @Query private var members: [Member]
    @Query private var roles: [Role]
    @Query private var meetings: [Meeting]

    private var report: MemberRoleDetailReport {
        MemberRoleDetailReport.build(members: members, roles: roles, meetings: meetings, asOf: Date())
    }

    var body: some View {
        ScrollView {
            MemberDetailTable(report: report)
        }
        .navigationTitle("Member Role Detail")
    }
}

// MARK: - The sheet (shared by preview and PDF)

struct MemberDetailTable: View {
    let report: MemberRoleDetailReport

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Member Role Detail").font(.title2.bold())
                Text("As of \(report.asOf.formatted(date: .abbreviated, time: .omitted))")
                    .foregroundStyle(.secondary)
            }

            if report.sections.isEmpty {
                Text("No active members.").foregroundStyle(.secondary)
            } else {
                ForEach(report.sections) { section in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(section.memberName)
                            .font(.headline)
                        ForEach(section.entries) { entry in
                            HStack(alignment: .firstTextBaseline) {
                                Text(entry.roleName)
                                Spacer(minLength: 12)
                                Text(recency(entry.daysAgo))
                                    .frame(width: 110, alignment: .trailing)
                                    .foregroundStyle(entry.daysAgo == nil ? .secondary : .primary)
                            }
                            .font(.callout)
                        }
                    }
                    .padding(.bottom, 6)
                }
            }
        }
        .padding(24)
        .frame(width: 380, alignment: .leading)
        .background(Color.white)
        .foregroundStyle(.black)
        .environment(\.colorScheme, .light)
    }

    private func recency(_ days: Int?) -> String {
        guard let days else { return "never" }
        switch days {
        case 0: return "today"
        case 1: return "1 day ago"
        default: return "\(days) days ago"
        }
    }
}

// MARK: - PDF rendering

@MainActor
enum MemberDetailPDF {
    static func render(_ report: MemberRoleDetailReport) -> Data {
        let renderer = ImageRenderer(content: MemberDetailTable(report: report))
        renderer.isOpaque = true

        let pdfData = NSMutableData()
        renderer.render { size, drawInContext in
            var mediaBox = CGRect(origin: .zero, size: size)
            guard let consumer = CGDataConsumer(data: pdfData as CFMutableData),
                  let pdfContext = CGContext(consumer: consumer, mediaBox: &mediaBox, nil)
            else { return }
            pdfContext.beginPDFPage(nil)
            drawInContext(pdfContext)
            pdfContext.endPDFPage()
            pdfContext.closePDF()
        }
        return pdfData as Data
    }
}

#Preview {
    NavigationStack {
        MemberDetailPreview()
    }
    .modelContainer(PreviewData.container)
}
