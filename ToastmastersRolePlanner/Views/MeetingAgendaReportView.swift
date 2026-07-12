import SwiftUI
import SwiftData
import CoreGraphics
import UniformTypeIdentifiers
import AppKit
import PDFKit

// A4 portrait and column widths (content width = 595 - 2*36 = 523).
private let agendaPageWidth: CGFloat = 595
private let agendaPageHeight: CGFloat = 842
private let agendaMargin: CGFloat = 36

// Column widths sum to the full content width (595 - 2*36 = 523) so the rows
// span the same width as the theme/quote fields above them. The name (Member)
// column takes the extra space.
private let colStart: CGFloat = 50
private let colRole: CGFloat = 170
private let colUser: CGFloat = 165
private let colTime: CGFloat = 46

let oaklandsCommittee: [(role: String, name: String)] = [
    ("President", "Jill de Jong"),
    ("VP Membership", "Ange Newman"),
    ("VP Education", "Shen Mansell"),
    ("VP Public Relations", "Barbara Forster"),
    ("Treasurer", "Alex Ferizis"),
    ("Secretary", "Claire Minty"),
    ("Sergeant at Arms", "Dinuka Gunawardena"),
    ("Previous President", "Alex Davies")
]

let oaklandsMission = "The mission of a Toastmasters club is to provide a mutually supportive and positive learning environment to develop communication and leadership skills, which in turn foster self-confidence and personal growth."

// MARK: - Report (controls + preview)

struct MeetingAgendaReportView: View {
    @Query private var meetings: [Meeting]
    @Query private var roles: [Role]

    @State private var start = Calendar.current.startOfDay(for: Date())
    @State private var end = Calendar.current.date(byAdding: .day, value: 56, to: Date()) ?? Date()

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
                    exportPDFs()
                } label: {
                    Label("Export PDFs…", systemImage: "square.and.arrow.up")
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
        .alert("Export failed", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    /// Saves each meeting's agenda to its own PDF in a user-chosen folder, named
    /// e.g. "2026 07 06 - July 06 Oaklands Toastmasters Agenda.pdf" — the leading
    /// ISO-style date sorts chronologically, the second is for easy reading.
    /// Existing files of the same name are overwritten.
    @MainActor
    private func exportPDFs() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Save Agendas"
        panel.message = "Choose a folder to save the meeting agendas"
        guard panel.runModal() == .OK, let folder = panel.url else { return }

        let formatter = DateFormatter()
        // e.g. "2026 07 06 - July 06" — sortable prefix, readable suffix.
        formatter.dateFormat = "yyyy MM dd' - 'MMMM dd"
        do {
            for agenda in agendas {
                let data = MeetingAgendaPDF.render([agenda])
                let filename = "\(formatter.string(from: agenda.date)) Oaklands Toastmasters Agenda.pdf"
                try data.write(to: folder.appendingPathComponent(filename))
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - One A4 agenda page

struct MeetingAgendaPage: View {
    let agenda: MeetingAgenda

    private let committee = oaklandsCommittee
    private let mission = oaklandsMission

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Oaklands Toastmasters - \(agenda.date.formatted(date: .complete, time: .omitted))")
                        .font(.title3.bold())

                    // Editable Theme / Quote fields.
                    VStack(alignment: .leading, spacing: 4) {
                        labelledField("Theme :", agenda.theme)
                        labelledField("Quote :", "")
                        labelledField("Author:", "")
                    }
                }
                Spacer()
                if let logo = NSImage(named: "Toastmasters-district-72") {
                    Image(nsImage: logo)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                        .frame(width: 70, height: 70)
                }
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
            .padding(.horizontal, 3)
            .padding(.vertical, 3)
            .frame(width: width, alignment: alignment)
    }

    /// Each cell fills the full row height so the white/grey background is a
    /// solid band even when a name wraps to two lines. Cells stay separate text
    /// objects so they remain individually editable in the exported PDF.
    private func cell(_ text: String, _ width: CGFloat, _ alignment: Alignment) -> some View {
        Text(text)
            .font(.system(size: 11))
            .padding(.horizontal, 3)
            .padding(.vertical, 3)
            .frame(width: width, alignment: alignment)
            .frame(maxHeight: .infinity)
    }
}

// MARK: - Multi-page PDF (one page per meeting)

// One drawing instruction in top-left page coordinates.
private enum AgendaDraw {
    case text(String, CGRect, NSFont, NSTextAlignment, NSColor, wrap: Bool)
    case fill(CGRect, NSColor)
    case image(NSImage, CGRect)
}

// A fillable field in top-left page coordinates.
private struct AgendaField {
    var rect: CGRect
    var value: String
    var name: String
    var alignment: NSTextAlignment = .left
    var fontSize: CGFloat = 11
}

@MainActor
enum MeetingAgendaPDF {
    static func render(_ agendas: [MeetingAgenda]) -> Data {
        // Pass 1: draw the static content for every page into a PDF.
        let pdfData = NSMutableData()
        var mediaBox = CGRect(x: 0, y: 0, width: agendaPageWidth, height: agendaPageHeight)
        guard let consumer = CGDataConsumer(data: pdfData as CFMutableData),
              let ctx = CGContext(consumer: consumer, mediaBox: &mediaBox, nil)
        else { return Data() }

        let layouts = agendas.map { layout(for: $0) }
        for layout in layouts {
            ctx.beginPDFPage(nil)
            ctx.saveGState()
            // Flip to a top-left origin so the layout coordinates draw upright.
            ctx.translateBy(x: 0, y: agendaPageHeight)
            ctx.scaleBy(x: 1, y: -1)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
            for command in layout.draws { execute(command) }
            NSGraphicsContext.restoreGraphicsState()
            ctx.restoreGState()
            ctx.endPDFPage()
        }
        ctx.closePDF()

        // Pass 2: re-open and overlay fillable form fields.
        guard let document = PDFDocument(data: pdfData as Data) else { return pdfData as Data }
        for (index, layout) in layouts.enumerated() {
            guard let page = document.page(at: index) else { continue }
            for field in layout.fields {
                let bounds = CGRect(
                    x: field.rect.minX,
                    y: agendaPageHeight - field.rect.minY - field.rect.height,
                    width: field.rect.width,
                    height: field.rect.height
                )
                let annotation = PDFAnnotation(bounds: bounds, forType: .widget, withProperties: nil)
                annotation.widgetFieldType = .text
                annotation.fieldName = field.name
                annotation.widgetStringValue = field.value
                annotation.alignment = field.alignment
                annotation.font = NSFont.systemFont(ofSize: field.fontSize)
                annotation.fontColor = .black
                annotation.backgroundColor = .clear
                let border = PDFBorder()
                border.lineWidth = 0
                annotation.border = border
                page.addAnnotation(annotation)
            }
        }
        return document.dataRepresentation() ?? (pdfData as Data)
    }

    private static func execute(_ command: AgendaDraw) {
        switch command {
        case let .text(string, rect, font, alignment, color, wrap):
            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = alignment
            paragraph.lineBreakMode = wrap ? .byWordWrapping : .byTruncatingTail
            NSString(string: string).draw(in: rect, withAttributes: [
                .font: font, .foregroundColor: color, .paragraphStyle: paragraph
            ])
        case let .fill(rect, color):
            color.setFill()
            NSBezierPath(rect: rect).fill()
        case let .image(image, rect):
            image.draw(in: rect)
        }
    }

    private static func clock(_ seconds: Int) -> String {
        let hour = (seconds / 3600) % 24
        let minute = (seconds % 3600) / 60
        let hour12 = hour % 12 == 0 ? 12 : hour % 12
        return String(format: "%d:%02d", hour12, minute)
    }

    private static func layout(for agenda: MeetingAgenda) -> (draws: [AgendaDraw], fields: [AgendaField]) {
        var draws: [AgendaDraw] = []
        var fields: [AgendaField] = []

        let left = agendaMargin
        let pad: CGFloat = 3
        let tableWidth = colStart + colRole + colUser + colTime * 3
        let body = NSFont.systemFont(ofSize: 11)
        let label = NSFont.systemFont(ofSize: 12, weight: .semibold)
        let id = agenda.id.uuidString

        // Column x-origins (from the page's left margin).
        let xStart = left
        let xRole = left + colStart
        let xMember = left + colStart + colRole
        let xGreen = xMember + colUser
        let xYellow = xGreen + colTime
        let xRed = xYellow + colTime

        var y = agendaMargin

        // Logo in the top-right corner, aligned with the title.
        let logoSize: CGFloat = 70
        if let logo = NSImage(named: "Toastmasters-district-72") {
            draws.append(.image(logo, CGRect(x: left + tableWidth - logoSize, y: y, width: logoSize, height: logoSize)))
        }
        // Theme/Quote fields stop short of the logo so they don't run under it.
        let topFieldWidth = tableWidth - 58 - logoSize - 10

        draws.append(.text("Oaklands Toastmasters - \(agenda.date.formatted(date: .complete, time: .omitted))",
                           CGRect(x: left, y: y, width: tableWidth - logoSize - 10, height: 22),
                           NSFont.boldSystemFont(ofSize: 15), .left, .black, wrap: false))
        y += 30

        draws.append(.text("Theme :", CGRect(x: left, y: y, width: 56, height: 16), label, .left, .black, wrap: false))
        fields.append(AgendaField(rect: CGRect(x: left + 58, y: y, width: topFieldWidth, height: 16), value: agenda.theme, name: "theme-\(id)"))
        y += 22
        draws.append(.text("Quote :", CGRect(x: left, y: y, width: 56, height: 16), label, .left, .black, wrap: false))
        fields.append(AgendaField(rect: CGRect(x: left + 58, y: y, width: topFieldWidth, height: 16), value: "", name: "quote-\(id)"))
        y += 26

        // Header row.
        let headerFont = NSFont.boldSystemFont(ofSize: 9)
        draws.append(.text("Start", CGRect(x: xStart + pad, y: y, width: colStart - pad, height: 14), headerFont, .left, .black, wrap: false))
        draws.append(.text("Role", CGRect(x: xRole + pad, y: y, width: colRole - pad, height: 14), headerFont, .left, .black, wrap: false))
        draws.append(.text("Member", CGRect(x: xMember + pad, y: y, width: colUser - pad, height: 14), headerFont, .left, .black, wrap: false))
        draws.append(.text("Green", CGRect(x: xGreen, y: y, width: colTime, height: 14), headerFont, .center, .black, wrap: false))
        draws.append(.text("Yellow", CGRect(x: xYellow, y: y, width: colTime, height: 14), headerFont, .center, .black, wrap: false))
        draws.append(.text("Red", CGRect(x: xRed, y: y, width: colTime, height: 14), headerFont, .center, .black, wrap: false))
        y += 16
        draws.append(.fill(CGRect(x: left, y: y, width: tableWidth, height: 0.7), .black))
        y += 2

        let rowH: CGFloat = 16
        let breakColor = NSColor.gray.withAlphaComponent(0.6)
        for (i, row) in agenda.rows.enumerated() {
            if row.isBreak {
                y += 4
                draws.append(.fill(CGRect(x: left, y: y, width: tableWidth, height: 0.5), breakColor))
                y += 5
            }
            if i.isMultiple(of: 2) {
                draws.append(.fill(CGRect(x: left, y: y, width: tableWidth, height: rowH), NSColor(white: 0.92, alpha: 1)))
            }
            // Start is computed (7:15 + red-above + buffers) but left editable.
            fields.append(AgendaField(rect: CGRect(x: xStart + pad - 1, y: y, width: colStart - pad, height: rowH), value: clock(row.startSeconds), name: "start-\(id)-\(i)"))
            draws.append(.text(row.roleLabel, CGRect(x: xRole + pad, y: y + 2, width: colRole - pad, height: 13), body, .left, .black, wrap: false))
            // Member and the three time signals are all fillable fields.
            // A trailing space is appended to the name: without it Preview's
            // generated appearance stream clips the last word of names that
            // nearly fill the field, hiding the person's second name until a
            // space is typed manually.
            let memberValue = row.user.isEmpty ? "" : row.user + " "
            fields.append(AgendaField(rect: CGRect(x: xMember + 1, y: y, width: colUser - 2, height: rowH), value: memberValue, name: "member-\(id)-\(i)"))
            fields.append(AgendaField(rect: CGRect(x: xGreen, y: y, width: colTime, height: rowH), value: row.green.asMMSS, name: "green-\(id)-\(i)", alignment: .center))
            fields.append(AgendaField(rect: CGRect(x: xYellow, y: y, width: colTime, height: rowH), value: row.yellow.asMMSS, name: "yellow-\(id)-\(i)", alignment: .center))
            fields.append(AgendaField(rect: CGRect(x: xRed, y: y, width: colTime, height: rowH), value: row.red.asMMSS, name: "red-\(id)-\(i)", alignment: .center))
            y += rowH
            if row.isBreak {
                y += 5
                draws.append(.fill(CGRect(x: left, y: y, width: tableWidth, height: 0.5), breakColor))
                y += 4
            }
        }

        y += 8
        let smallGray = NSColor.darkGray
        let noteFont = NSFont.systemFont(ofSize: 10)
        // Label stays static; the names are editable fields (so they can be
        // corrected or filled in even when empty).
        draws.append(.text("No role:", CGRect(x: left, y: y, width: 48, height: 14), noteFont, .left, smallGray, wrap: false))
        fields.append(AgendaField(rect: CGRect(x: left + 50, y: y - 1, width: tableWidth - 50, height: 14), value: agenda.noRole.joined(separator: ", "), name: "norole-\(id)", fontSize: 10))
        y += 16
        draws.append(.text("Apologies:", CGRect(x: left, y: y, width: 60, height: 14), noteFont, .left, smallGray, wrap: false))
        fields.append(AgendaField(rect: CGRect(x: left + 62, y: y - 1, width: tableWidth - 62, height: 14), value: agenda.apologies.joined(separator: ", "), name: "apologies-\(id)", fontSize: 10))
        y += 16

        // Committee footer, anchored near the bottom.
        let footerHeight: CGFloat = 116
        var fy = max(y + 12, agendaPageHeight - agendaMargin - footerHeight)
        draws.append(.fill(CGRect(x: left, y: fy, width: tableWidth, height: 0.5), breakColor))
        fy += 6
        draws.append(.text("Oaklands Club Committee", CGRect(x: left, y: fy, width: 300, height: 14), NSFont.boldSystemFont(ofSize: 10), .left, .black, wrap: false))
        fy += 16

        let roleFont = NSFont.boldSystemFont(ofSize: 9)
        let nameFont = NSFont.systemFont(ofSize: 9)
        let colGap: CGFloat = 245
        let nameOffset: CGFloat = 105
        for r in 0..<4 {
            let rowY = fy + CGFloat(r) * 12
            let leftEntry = oaklandsCommittee[r]
            let rightEntry = oaklandsCommittee[r + 4]
            draws.append(.text(leftEntry.role, CGRect(x: left, y: rowY, width: nameOffset, height: 12), roleFont, .left, .black, wrap: false))
            draws.append(.text(leftEntry.name, CGRect(x: left + nameOffset, y: rowY, width: colGap - nameOffset, height: 12), nameFont, .left, .black, wrap: false))
            draws.append(.text(rightEntry.role, CGRect(x: left + colGap, y: rowY, width: nameOffset, height: 12), roleFont, .left, .black, wrap: false))
            draws.append(.text(rightEntry.name, CGRect(x: left + colGap + nameOffset, y: rowY, width: 140, height: 12), nameFont, .left, .black, wrap: false))
        }
        fy += 4 * 12 + 6
        draws.append(.text(oaklandsMission, CGRect(x: left, y: fy, width: tableWidth, height: 40), NSFont.systemFont(ofSize: 8), .left, .gray, wrap: true))

        return (draws, fields)
    }
}

#Preview {
    NavigationStack {
        MeetingAgendaReportView()
    }
    .modelContainer(PreviewData.container)
}
