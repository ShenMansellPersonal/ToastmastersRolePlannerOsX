import SwiftUI
import SwiftData
import CoreGraphics
import UniformTypeIdentifiers

// Shared table column widths (used by both the on-screen table and the PDF).
private let memberColumnWidth: CGFloat = 160
private let roleColumnWidth: CGFloat = 64
private let totalColumnWidth: CGFloat = 56
private let tablePadding: CGFloat = 24

// Gridline / cell border colour.
private let gridLineColor = Color.black

// MARK: - Role Participation report (controls + preview)

struct RoleParticipationReportView: View {
    @Query private var members: [Member]
    @Query private var roles: [Role]
    @Query private var meetings: [Meeting]

    @State private var start = Calendar.current.date(byAdding: .month, value: -6, to: Date()) ?? Date()
    @State private var end = Date()

    @State private var showingExporter = false
    @State private var pdfDocument = ReportPDFDocument(data: Data())
    @State private var errorMessage: String?

    private var report: RoleReport {
        RoleReport.build(members: members, roles: roles, meetings: meetings, start: start, end: end)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 16) {
                DatePicker("From", selection: $start, displayedComponents: [.date])
                DatePicker("To", selection: $end, displayedComponents: [.date])
                Button("Future") {
                    start = Calendar.current.startOfDay(for: Date())
                    end = Calendar.current.date(byAdding: .year, value: 1, to: Date()) ?? Date()
                }
                .help("Show today through one year from now")
                Spacer()
                Button {
                    exportPDF()
                } label: {
                    Label("Export PDF…", systemImage: "square.and.arrow.up")
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .padding()

            Divider()

            ScrollView([.horizontal, .vertical]) {
                ReportTable(report: report)
            }
        }
        .navigationTitle("Role Participation")
        .fileExporter(
            isPresented: $showingExporter,
            document: pdfDocument,
            contentType: .pdf,
            defaultFilename: "Role Participation Report"
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
        pdfDocument = ReportPDFDocument(data: ReportPDF.render(report))
        showingExporter = true
    }
}

// MARK: - The table (shared by preview and PDF)

struct ReportTable: View {
    let report: RoleReport

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Role Participation Report")
                    .font(.title2.bold())
                Text("\(report.start.formatted(date: .abbreviated, time: .omitted)) – \(report.end.formatted(date: .abbreviated, time: .omitted))")
                    .foregroundStyle(.secondary)
            }

            if report.rows.isEmpty || report.roleNames.isEmpty {
                Text("No active members or roles to report.")
                    .foregroundStyle(.secondary)
            } else {
                Grid(alignment: .leading, horizontalSpacing: 0, verticalSpacing: 0) {
                    GridRow {
                        headerCell("Member", width: memberColumnWidth, alignment: .leading)
                        ForEach(Array(report.roleNames.enumerated()), id: \.offset) { _, name in
                            headerCell(name, width: roleColumnWidth, alignment: .center)
                        }
                        headerCell("Total", width: totalColumnWidth, alignment: .center)
                        headerCell("TT speaker", width: roleColumnWidth, alignment: .center)
                        headerCell("No role", width: roleColumnWidth, alignment: .center)
                        headerCell("Absent", width: roleColumnWidth, alignment: .center)
                    }

                    ForEach(Array(report.rows.enumerated()), id: \.element.id) { rowIndex, row in
                        GridRow {
                            bodyCell(row.memberName, width: memberColumnWidth, alignment: .leading, shaded: rowIndex.isMultiple(of: 2))
                            ForEach(Array(row.counts.enumerated()), id: \.offset) { _, count in
                                bodyCell(count == 0 ? "" : "\(count)", width: roleColumnWidth, alignment: .center, shaded: rowIndex.isMultiple(of: 2))
                            }
                            bodyCell("\(row.total)", width: totalColumnWidth, alignment: .center, shaded: rowIndex.isMultiple(of: 2), bold: true)
                            bodyCell(row.ttSpeaker == 0 ? "" : "\(row.ttSpeaker)", width: roleColumnWidth, alignment: .center, shaded: rowIndex.isMultiple(of: 2))
                            bodyCell(row.noRole == 0 ? "" : "\(row.noRole)", width: roleColumnWidth, alignment: .center, shaded: rowIndex.isMultiple(of: 2))
                            bodyCell(row.absent == 0 ? "" : "\(row.absent)", width: roleColumnWidth, alignment: .center, shaded: rowIndex.isMultiple(of: 2))
                        }
                    }

                    GridRow {
                        headerCell("Total", width: memberColumnWidth, alignment: .leading)
                        ForEach(Array(report.columnTotals.enumerated()), id: \.offset) { _, total in
                            headerCell(total == 0 ? "" : "\(total)", width: roleColumnWidth, alignment: .center)
                        }
                        headerCell("\(report.grandTotal)", width: totalColumnWidth, alignment: .center)
                        headerCell(report.ttSpeakerTotal == 0 ? "" : "\(report.ttSpeakerTotal)", width: roleColumnWidth, alignment: .center)
                        headerCell(report.noRoleTotal == 0 ? "" : "\(report.noRoleTotal)", width: roleColumnWidth, alignment: .center)
                        headerCell(report.absentTotal == 0 ? "" : "\(report.absentTotal)", width: roleColumnWidth, alignment: .center)
                    }
                }
                .border(gridLineColor, width: 1)
            }
        }
        .padding(tablePadding)
        .background(Color.white)
        .foregroundStyle(.black)
        .tint(.black)
        .environment(\.colorScheme, .light)
    }

    private func headerCell(_ text: String, width: CGFloat, alignment: Alignment) -> some View {
        Text(text)
            .font(.caption2.bold())
            .multilineTextAlignment(alignment == .leading ? .leading : .center)
            .frame(width: width, alignment: alignment)
            .frame(maxHeight: .infinity)
            .padding(.vertical, 5)
            .padding(.horizontal, 4)
            .background(Color.gray.opacity(0.10))
            .border(gridLineColor, width: 0.5)
    }

    private func bodyCell(_ text: String, width: CGFloat, alignment: Alignment, shaded: Bool, bold: Bool = false) -> some View {
        Text(text)
            .font(.caption)
            .fontWeight(bold ? .semibold : .regular)
            .frame(width: width, alignment: alignment)
            .frame(maxHeight: .infinity)
            .padding(.vertical, 4)
            .padding(.horizontal, 4)
            .background(shaded ? Color.gray.opacity(0.06) : Color.white)
            .border(gridLineColor, width: 0.5)
    }
}

// MARK: - PDF rendering

@MainActor
enum ReportPDF {
    static func render(_ report: RoleReport) -> Data {
        let width = memberColumnWidth
            + CGFloat(report.roleNames.count) * roleColumnWidth
            + totalColumnWidth
            + roleColumnWidth * 3   // TT speaker + No role + Absent columns
            + tablePadding * 2

        let content = ReportTable(report: report)
            .frame(width: max(width, 320), alignment: .topLeading)
            .background(Color.white)

        let renderer = ImageRenderer(content: content)
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

/// Wraps PDF data for SwiftUI's `.fileExporter`.
struct ReportPDFDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.pdf] }

    var data: Data

    init(data: Data) { self.data = data }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

#Preview {
    NavigationStack {
        RoleParticipationReportView()
    }
    .modelContainer(PreviewData.container)
}
