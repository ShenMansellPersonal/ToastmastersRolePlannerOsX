import SwiftUI
import SwiftData
import CoreGraphics
import UniformTypeIdentifiers

// A4 portrait page geometry (points @ 72dpi) and estimated row heights used to
// decide page breaks.
private let a4Width: CGFloat = 595
private let a4Height: CGFloat = 842
private let pageMargin: CGFloat = 36
private let titleBlockHeight: CGFloat = 58      // title + subtitle (first page only)
private let sectionSpacing: CGFloat = 16        // gap between member blocks
private let memberHeaderHeight: CGFloat = 22    // member name + spacing to rows
private let entryRowHeight: CGFloat = 16        // one role line (12pt body)
private let sectionBottomPadding: CGFloat = 6

private func estimatedHeight(of section: MemberRoleDetailReport.MemberSection) -> CGFloat {
    memberHeaderHeight + CGFloat(section.entries.count) * entryRowHeight + sectionBottomPadding
}

/// Packs member sections into pages so a member's block is never split across a
/// page; if the next block won't fit, it starts a new page.
private func paginate(_ sections: [MemberRoleDetailReport.MemberSection]) -> [[MemberRoleDetailReport.MemberSection]] {
    let usable = a4Height - pageMargin * 2 - 8   // small safety margin
    var pages: [[MemberRoleDetailReport.MemberSection]] = []
    var current: [MemberRoleDetailReport.MemberSection] = []
    var used = titleBlockHeight + sectionSpacing  // first page carries the title

    for section in sections {
        let needed = estimatedHeight(of: section) + (current.isEmpty ? 0 : sectionSpacing)
        if !current.isEmpty, used + needed > usable {
            pages.append(current)
            current = []
            used = 0   // later pages have no title block
        }
        current.append(section)
        used += estimatedHeight(of: section) + (current.count == 1 ? 0 : sectionSpacing)
    }
    if !current.isEmpty { pages.append(current) }
    return pages.isEmpty ? [[]] : pages
}

// MARK: - Member Role Detail report (controls + paginated preview)

struct MemberRoleDetailReportView: View {
    @Query private var members: [Member]
    @Query private var roles: [Role]
    @Query private var meetings: [Meeting]

    @State private var showingExporter = false
    @State private var pdfDocument = ReportPDFDocument(data: Data())
    @State private var errorMessage: String?

    private var report: MemberRoleDetailReport {
        MemberRoleDetailReport.build(members: members, roles: roles, meetings: meetings, asOf: Date())
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Days since each member last performed each role.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    exportPDF()
                } label: {
                    Label("Export PDF…", systemImage: "square.and.arrow.up")
                }
            }
            .padding()

            Divider()

            ScrollView([.horizontal, .vertical]) {
                let pages = paginate(report.sections)
                VStack(spacing: 20) {
                    ForEach(Array(pages.enumerated()), id: \.offset) { index, page in
                        MemberDetailPage(sections: page, showTitle: index == 0, asOf: report.asOf)
                            .shadow(radius: 2)
                    }
                }
                .padding(20)
            }
        }
        .navigationTitle("Member Role Detail")
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
        pdfDocument = ReportPDFDocument(data: MemberDetailPDF.render(report))
        showingExporter = true
    }
}

// MARK: - One A4 page (shared by preview and PDF)

struct MemberDetailPage: View {
    let sections: [MemberRoleDetailReport.MemberSection]
    let showTitle: Bool
    let asOf: Date

    var body: some View {
        VStack(alignment: .leading, spacing: sectionSpacing) {
            if showTitle {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Member Role Detail").font(.title2.bold())
                    Text("As of \(asOf.formatted(date: .abbreviated, time: .omitted))")
                        .foregroundStyle(.secondary)
                }
            }

            ForEach(sections) { section in
                VStack(alignment: .leading, spacing: 3) {
                    Text(section.memberName).font(.headline)
                    ForEach(section.entries) { entry in
                        HStack(alignment: .firstTextBaseline) {
                            Text(entry.roleName).lineLimit(1)
                            Spacer(minLength: 12)
                            Text(recency(entry.daysAgo))
                                .frame(width: 110, alignment: .trailing)
                                .foregroundStyle(entry.daysAgo == nil ? .secondary : .primary)
                        }
                        .font(.system(size: 12))
                    }
                }
                .padding(.bottom, sectionBottomPadding)
            }

            Spacer(minLength: 0)
        }
        .padding(pageMargin)
        .frame(width: a4Width, height: a4Height, alignment: .topLeading)
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

// MARK: - Multi-page PDF rendering

@MainActor
enum MemberDetailPDF {
    static func render(_ report: MemberRoleDetailReport) -> Data {
        let pages = paginate(report.sections)
        let pdfData = NSMutableData()
        var mediaBox = CGRect(x: 0, y: 0, width: a4Width, height: a4Height)
        guard let consumer = CGDataConsumer(data: pdfData as CFMutableData),
              let pdfContext = CGContext(consumer: consumer, mediaBox: &mediaBox, nil)
        else { return Data() }

        for (index, page) in pages.enumerated() {
            let view = MemberDetailPage(sections: page, showTitle: index == 0, asOf: report.asOf)
            let renderer = ImageRenderer(content: view)
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
        MemberRoleDetailReportView()
    }
    .modelContainer(PreviewData.container)
}
