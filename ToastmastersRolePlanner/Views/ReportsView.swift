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
                Menu {
                    ForEach(DatePreset.allCases) { preset in
                        Button(preset.rawValue) { applyPreset(preset) }
                    }
                } label: {
                    Label("Presets", systemImage: "calendar.badge.clock")
                }
                .fixedSize()
                .help("Populate the date range from a preset")

                DatePicker("From", selection: $start, displayedComponents: [.date])
                DatePicker("To", selection: $end, displayedComponents: [.date])
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
                VStack(alignment: .leading, spacing: 28) {
                    ReportTable(report: report, mode: .counts)
                    ReportTable(report: report, mode: .percentage)
                }
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

    /// Quick date-range presets offered in the dropdown.
    private enum DatePreset: String, CaseIterable, Identifiable {
        case lastMonth = "Last month"
        case last3Months = "Last 3 months"
        case last6Months = "Last 6 months"
        case next4Meetings = "Next 4 meetings"
        case allFutureMeetings = "All future meetings"
        var id: String { rawValue }
    }

    /// Populates the From/To range from the chosen preset. The "meetings"
    /// presets look at the scheduled meeting dates from today onward.
    private func applyPreset(_ preset: DatePreset) {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        // Distinct upcoming meeting days (today or later), in order.
        let upcoming = Set(meetings.map { calendar.startOfDay(for: $0.date) })
            .filter { $0 >= today }
            .sorted()

        switch preset {
        case .lastMonth:
            start = calendar.date(byAdding: .month, value: -1, to: today) ?? today
            end = today
        case .last3Months:
            start = calendar.date(byAdding: .month, value: -3, to: today) ?? today
            end = today
        case .last6Months:
            start = calendar.date(byAdding: .month, value: -6, to: today) ?? today
            end = today
        case .next4Meetings:
            start = today
            // The 4th upcoming meeting, or the last one if there are fewer than 4.
            end = upcoming.count >= 4 ? upcoming[3] : (upcoming.last ?? today)
        case .allFutureMeetings:
            start = today
            end = upcoming.last ?? today
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
    enum Mode { case counts, percentage }

    let report: RoleReport
    var mode: Mode = .counts

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(mode == .counts ? "Role Participation Report" : "Participation Rate — % of meetings attended")
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
                        let shaded = rowIndex.isMultiple(of: 2)
                        GridRow {
                            bodyCell(row.memberName, width: memberColumnWidth, alignment: .leading, shaded: shaded)
                            ForEach(Array(row.counts.enumerated()), id: \.offset) { _, count in
                                bodyCell(value(count, present: row.presentMeetings), width: roleColumnWidth, alignment: .center, shaded: shaded)
                            }
                            bodyCell(value(row.total, present: row.presentMeetings, keepZero: true), width: totalColumnWidth, alignment: .center, shaded: shaded, bold: true)
                            bodyCell(value(row.ttSpeaker, present: row.presentMeetings), width: roleColumnWidth, alignment: .center, shaded: shaded)
                            bodyCell(value(row.noRole, present: row.presentMeetings), width: roleColumnWidth, alignment: .center, shaded: shaded)
                            bodyCell(value(row.absent, present: row.presentMeetings), width: roleColumnWidth, alignment: .center, shaded: shaded)
                        }
                    }

                    // The percentage page omits the column-totals row (a sum of
                    // rates isn't meaningful).
                    if mode == .counts {
                        GridRow {
                            headerCell("Total", width: memberColumnWidth, alignment: .leading)
                            ForEach(Array(report.columnTotals.enumerated()), id: \.offset) { _, total in
                                headerCell(value(total, present: report.presentMeetingsTotal), width: roleColumnWidth, alignment: .center)
                            }
                            headerCell(value(report.grandTotal, present: report.presentMeetingsTotal, keepZero: true), width: totalColumnWidth, alignment: .center)
                            headerCell(value(report.ttSpeakerTotal, present: report.presentMeetingsTotal), width: roleColumnWidth, alignment: .center)
                            headerCell(value(report.noRoleTotal, present: report.presentMeetingsTotal), width: roleColumnWidth, alignment: .center)
                            headerCell(value(report.absentTotal, present: report.presentMeetingsTotal), width: roleColumnWidth, alignment: .center)
                        }
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

    /// Formats a cell: the raw count on the counts page, or `count / present` as
    /// a 2-dp percentage (e.g. "5.45%") on the rate page. Zero reads as blank
    /// unless `keepZero` (used by the Total column), and a zero denominator on
    /// the rate page also blanks the cell.
    private func value(_ count: Int, present: Int, keepZero: Bool = false) -> String {
        switch mode {
        case .counts:
            return count == 0 && !keepZero ? "" : "\(count)"
        case .percentage:
            guard present > 0, count != 0 || keepZero else { return "" }
            return String(format: "%.2f%%", Double(count) / Double(present) * 100)
        }
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

        // Page 1: counts. Page 2: participation rate (%). Same rows and columns.
        let tables: [ReportTable] = [
            ReportTable(report: report, mode: .counts),
            ReportTable(report: report, mode: .percentage)
        ]

        let pdfData = NSMutableData()
        var pdfContext: CGContext?
        for table in tables {
            let content = table
                .frame(width: max(width, 320), alignment: .topLeading)
                .background(Color.white)
            let renderer = ImageRenderer(content: content)
            renderer.isOpaque = true
            renderer.render { size, drawInContext in
                if pdfContext == nil {
                    var mediaBox = CGRect(origin: .zero, size: size)
                    guard let consumer = CGDataConsumer(data: pdfData as CFMutableData),
                          let ctx = CGContext(consumer: consumer, mediaBox: &mediaBox, nil)
                    else { return }
                    pdfContext = ctx
                }
                guard let ctx = pdfContext else { return }
                ctx.beginPDFPage(nil)
                drawInContext(ctx)
                ctx.endPDFPage()
            }
        }
        pdfContext?.closePDF()
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
