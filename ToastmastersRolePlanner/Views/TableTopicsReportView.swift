import SwiftUI
import SwiftData
import CoreGraphics
import UniformTypeIdentifiers

// Column widths (shared by the on-screen table and the PDF).
private let ttMemberColumnWidth: CGFloat = 200
private let ttCountColumnWidth: CGFloat = 120
private let ttRateColumnWidth: CGFloat = 160
private let ttTablePadding: CGFloat = 24
private let ttGridLineColor = Color.black

// MARK: - Table Topics report (controls + preview)

struct TableTopicsReportView: View {
    @Query private var members: [Member]
    @Query private var meetings: [Meeting]

    @State private var start: Date
    @State private var end: Date

    @State private var showingExporter = false
    @State private var pdfDocument = ReportPDFDocument(data: Data())
    @State private var errorMessage: String?

    init() {
        let range = TableTopicsReport.defaultRange()
        _start = State(initialValue: range.start)
        _end = State(initialValue: range.end)
    }

    private var report: TableTopicsReport {
        TableTopicsReport.build(members: members, meetings: meetings, start: start, end: end)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 16) {
                Button {
                    let range = TableTopicsReport.defaultRange()
                    start = range.start
                    end = range.end
                } label: {
                    Label("Reset dates", systemImage: "calendar.badge.clock")
                }
                .fixedSize()
                .help("Reset to 29 June 2026 (or 6 months ago) through yesterday")

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
                TableTopicsTable(report: report)
            }
        }
        .navigationTitle("Table Topics")
        .fileExporter(
            isPresented: $showingExporter,
            document: pdfDocument,
            contentType: .pdf,
            defaultFilename: "Table Topics Report"
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
        pdfDocument = ReportPDFDocument(data: TableTopicsPDF.render(report))
        showingExporter = true
    }
}

// MARK: - The table (shared by preview and PDF)

struct TableTopicsTable: View {
    let report: TableTopicsReport

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Table Topics Speakers")
                    .font(.title2.bold())
                Text("\(report.start.formatted(date: .abbreviated, time: .omitted)) – \(report.end.formatted(date: .abbreviated, time: .omitted)) - \(report.meetingCount) meetings")
                    .foregroundStyle(.secondary)
            }

            if report.rows.isEmpty {
                Text("No active members to report.")
                    .foregroundStyle(.secondary)
            } else {
                Grid(alignment: .leading, horizontalSpacing: 0, verticalSpacing: 0) {
                    GridRow {
                        headerCell("Member", width: ttMemberColumnWidth, alignment: .leading)
                        headerCell("Table Topics", width: ttCountColumnWidth, alignment: .center)
                        headerCell("Pick % (when present)", width: ttRateColumnWidth, alignment: .center)
                    }

                    ForEach(Array(report.rows.enumerated()), id: \.element.id) { rowIndex, row in
                        let shaded = rowIndex.isMultiple(of: 2)
                        GridRow {
                            bodyCell(row.memberName, width: ttMemberColumnWidth, alignment: .leading, shaded: shaded)
                            bodyCell("\(row.ttCount)", width: ttCountColumnWidth, alignment: .center, shaded: shaded)
                            bodyCell(rateString(row), width: ttRateColumnWidth, alignment: .center, shaded: shaded)
                        }
                    }
                }
                .border(ttGridLineColor, width: 1)
            }
        }
        .padding(ttTablePadding)
        .background(Color.white)
        .foregroundStyle(.black)
        .tint(.black)
        .environment(\.colorScheme, .light)
    }

    /// The rate as a 2-dp percentage. Never speaking — and attending no meetings
    /// at all — both read as 0.00%.
    private func rateString(_ row: TableTopicsReport.Row) -> String {
        String(format: "%.2f%%", row.rate ?? 0)
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
            .border(ttGridLineColor, width: 0.5)
    }

    private func bodyCell(_ text: String, width: CGFloat, alignment: Alignment, shaded: Bool) -> some View {
        Text(text)
            .font(.caption)
            .frame(width: width, alignment: alignment)
            .frame(maxHeight: .infinity)
            .padding(.vertical, 4)
            .padding(.horizontal, 4)
            .background(shaded ? Color.gray.opacity(0.06) : Color.white)
            .border(ttGridLineColor, width: 0.5)
    }
}

// MARK: - PDF rendering

@MainActor
enum TableTopicsPDF {
    static func render(_ report: TableTopicsReport) -> Data {
        let width = ttMemberColumnWidth + ttCountColumnWidth + ttRateColumnWidth + ttTablePadding * 2

        let content = TableTopicsTable(report: report)
            .frame(width: max(width, 320), alignment: .topLeading)
            .background(Color.white)

        let pdfData = NSMutableData()
        let renderer = ImageRenderer(content: content)
        renderer.isOpaque = true
        renderer.render { size, drawInContext in
            var mediaBox = CGRect(origin: .zero, size: size)
            guard let consumer = CGDataConsumer(data: pdfData as CFMutableData),
                  let ctx = CGContext(consumer: consumer, mediaBox: &mediaBox, nil)
            else { return }
            ctx.beginPDFPage(nil)
            drawInContext(ctx)
            ctx.endPDFPage()
            ctx.closePDF()
        }
        return pdfData as Data
    }
}

#Preview {
    NavigationStack {
        TableTopicsReportView()
    }
    .modelContainer(PreviewData.container)
}
