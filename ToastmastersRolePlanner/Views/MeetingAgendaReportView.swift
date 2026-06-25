import SwiftUI
import SwiftData
import CoreGraphics
import UniformTypeIdentifiers
import AppKit

// A4 portrait and column widths (content width = 595 - 2*36 = 523).
private let agendaPageWidth: CGFloat = 595
private let agendaPageHeight: CGFloat = 842
private let agendaMargin: CGFloat = 36

private let colStart: CGFloat = 55
private let colRole: CGFloat = 170
private let colUser: CGFloat = 110
private let colTime: CGFloat = 46

// MARK: - Report (controls + preview)

struct MeetingAgendaReportView: View {
    @Query private var meetings: [Meeting]
    @Query private var roles: [Role]

    @State private var start = Calendar.current.startOfDay(for: Date())
    @State private var end = Calendar.current.date(byAdding: .day, value: 56, to: Date()) ?? Date()

    @State private var showingExporter = false
    @State private var pdfDocument = ReportPDFDocument(data: Data())
    @State private var errorMessage: String?

    @Query private var members: [Member]

    private var agendas: [MeetingAgenda] {
        MeetingAgendaReport.build(
            meetings: meetings,
            rolesByKey: Role.lookup(roles),
            activeMembers: members.filter(\.isActive),
            start: start,
            end: end
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 16) {
                DatePicker("From", selection: $start, displayedComponents: [.date])
                DatePicker("To", selection: $end, displayedComponents: [.date])
                Spacer()
                Button {
                    exportPDF()
                } label: {
                    Label("Export PDF…", systemImage: "square.and.arrow.up")
                }
                .disabled(agendas.isEmpty)
            }
            .fixedSize(horizontal: false, vertical: true)
            .padding()

            Divider()

            ScrollView([.horizontal, .vertical]) {
                if agendas.isEmpty {
                    Text("No meetings in this date range.")
                        .foregroundStyle(.secondary)
                        .padding(40)
                } else {
                    VStack(spacing: 20) {
                        ForEach(agendas) { agenda in
                            MeetingAgendaPage(agenda: agenda)
                                .shadow(radius: 2)
                        }
                    }
                    .padding(20)
                }
            }
        }
        .navigationTitle("Meeting Agendas")
        .fileExporter(
            isPresented: $showingExporter,
            document: pdfDocument,
            contentType: .pdf,
            defaultFilename: "Meeting Agendas"
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
        pdfDocument = ReportPDFDocument(data: MeetingAgendaPDF.render(agendas))
        showingExporter = true
    }
}

// MARK: - One A4 agenda page

struct MeetingAgendaPage: View {
    let agenda: MeetingAgenda

    private let committee: [(role: String, name: String)] = [
        ("President", "Jill de Jong"),
        ("VP Membership", "Ange Newman"),
        ("VP Education", "Shen Mansell"),
        ("VP Public Relations", "Barbara Forster"),
        ("Treasurer", "Alex Ferizis"),
        ("Secretary", "Claire Minty"),
        ("Sergeant at Arms", "Dinuka Gunawardena"),
        ("Previous President", "Alex Davies")
    ]

    private let mission = "The mission of a Toastmasters club is to provide a mutually supportive and positive learning environment to develop communication and leadership skills, which in turn foster self-confidence and personal growth."

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Oaklands Toastmasters - \(agenda.date.formatted(date: .complete, time: .omitted))")
                .font(.title3.bold())

            // Editable Theme / Quote fields.
            VStack(alignment: .leading, spacing: 4) {
                labelledField("Theme :", agenda.theme)
                labelledField("Quote :", "")
            }

            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    headerCell("Start", colStart, .leading)
                    headerCell("Role", colRole, .leading)
                    headerCell("Member", colUser, .leading)
                    headerCell("Green", colTime, .center)
                    headerCell("Yellow", colTime, .center)
                    headerCell("Red", colTime, .center)
                }
                Rectangle().fill(Color.black).frame(height: 0.7)   // header underline

                ForEach(Array(agenda.rows.enumerated()), id: \.element.id) { index, row in
                    if row.isBreak { breakRule }
                    HStack(spacing: 0) {
                        cell(clockString(row.startSeconds), colStart, .leading)
                        cell(row.roleLabel, colRole, .leading)
                        cell(row.user, colUser, .leading)
                        cell(row.green.asMMSS, colTime, .center)
                        cell(row.yellow.asMMSS, colTime, .center)
                        cell(row.red.asMMSS, colTime, .center)
                    }
                    .background(index.isMultiple(of: 2) ? Color(white: 0.92) : Color.white)
                    if row.isBreak { breakRule }
                }
            }

            if !agenda.noRole.isEmpty {
                Text("No role: \(agenda.noRole.joined(separator: ", "))")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            if !agenda.apologies.isEmpty {
                Text("Apologies: \(agenda.apologies.joined(separator: ", "))")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            committeeFooter
        }
        .padding(agendaMargin)
        .frame(width: agendaPageWidth, height: agendaPageHeight, alignment: .topLeading)
        .background(Color.white)
        .foregroundStyle(.black)
        .environment(\.colorScheme, .light)
    }

    private func labelledField(_ label: String, _ value: String) -> some View {
        HStack(spacing: 6) {
            Text(label).font(.system(size: 12, weight: .semibold))
            Text(value).font(.system(size: 12))
            Spacer()
        }
    }

    // MARK: Committee footer

    private var committeeFooter: some View {
        VStack(alignment: .leading, spacing: 4) {
            Rectangle().fill(Color.gray.opacity(0.5)).frame(height: 0.5)
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Oaklands Club Committee").font(.system(size: 10, weight: .bold))
                    HStack(alignment: .top, spacing: 24) {
                        committeeTable(Array(committee.prefix(4)))
                        committeeTable(Array(committee.suffix(4)))
                    }
                    Text(mission)
                        .font(.system(size: 8))
                        .italic()
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: 420, alignment: .leading)
                }
                Spacer()
                if let logo = NSImage(named: "Toastmasters-district-72") {
                    Image(nsImage: logo)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                        .frame(width: 72, height: 72)
                }
            }
        }
    }

    private func committeeTable(_ entries: [(role: String, name: String)]) -> some View {
        Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 2) {
            ForEach(Array(entries.enumerated()), id: \.offset) { _, entry in
                GridRow {
                    Text(entry.role).font(.system(size: 9, weight: .semibold))
                    Text(entry.name).font(.system(size: 9))
                }
            }
        }
    }

    // MARK: Roles grid helpers

    /// A slim grey full-width line with extra spacing, used around the Break.
    private var breakRule: some View {
        Rectangle()
            .fill(Color.gray.opacity(0.5))
            .frame(height: 0.5)
            .padding(.vertical, 5)
    }

    private func clockString(_ seconds: Int) -> String {
        let hour = (seconds / 3600) % 24
        let minute = (seconds % 3600) / 60
        let hour12 = hour % 12 == 0 ? 12 : hour % 12
        return String(format: "%d:%02d", hour12, minute)
    }

    private func headerCell(_ text: String, _ width: CGFloat, _ alignment: Alignment) -> some View {
        Text(text)
            .font(.caption2.bold())
            .padding(.horizontal, 5)
            .padding(.vertical, 3)
            .frame(width: width, alignment: alignment)
    }

    /// Each cell fills the full row height so the white/grey background is a
    /// solid band even when a name wraps to two lines. Cells stay separate text
    /// objects so they remain individually editable in the exported PDF.
    private func cell(_ text: String, _ width: CGFloat, _ alignment: Alignment) -> some View {
        Text(text)
            .font(.system(size: 11))
            .padding(.horizontal, 5)
            .padding(.vertical, 3)
            .frame(width: width, alignment: alignment)
            .frame(maxHeight: .infinity)
    }
}

// MARK: - Multi-page PDF (one page per meeting)

@MainActor
enum MeetingAgendaPDF {
    static func render(_ agendas: [MeetingAgenda]) -> Data {
        let pdfData = NSMutableData()
        var mediaBox = CGRect(x: 0, y: 0, width: agendaPageWidth, height: agendaPageHeight)
        guard let consumer = CGDataConsumer(data: pdfData as CFMutableData),
              let pdfContext = CGContext(consumer: consumer, mediaBox: &mediaBox, nil)
        else { return Data() }

        for agenda in agendas {
            let renderer = ImageRenderer(content: MeetingAgendaPage(agenda: agenda))
            renderer.isOpaque = true
            renderer.render { _, drawInContext in
                pdfContext.beginPDFPage(nil)
                drawInContext(pdfContext)
                pdfContext.endPDFPage()
            }
        }
        pdfContext.closePDF()
        return pdfData as Data
    }
}

#Preview {
    NavigationStack {
        MeetingAgendaReportView()
    }
    .modelContainer(PreviewData.container)
}
