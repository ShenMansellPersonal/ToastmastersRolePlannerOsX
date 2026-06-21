import Foundation
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// CSV import/export for members. Columns: Name, Active, Notes, Joined.
enum MemberCSV {
    static let header = "Name,Active,Notes,Joined"

    private static let exportDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static let importDateFormats = ["yyyy-MM-dd", "dd/MM/yyyy", "d/M/yyyy", "d/M/yy"]

    // MARK: Export

    static func export(_ members: [Member]) -> String {
        var lines = [header]
        for member in members.sorted(by: { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }) {
            let fields = [
                member.name,
                member.isActive ? "Yes" : "No",
                member.notes,
                exportDateFormatter.string(from: member.joinedDate)
            ]
            lines.append(fields.map(escape).joined(separator: ","))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    // MARK: Import

    /// Inserts new members and updates existing ones (matched by name,
    /// case-insensitively). Returns how many were inserted vs updated.
    @discardableResult
    static func importing(_ text: String, into context: ModelContext, existing: [Member]) -> (inserted: Int, updated: Int) {
        let rows = parse(text)
        guard !rows.isEmpty else { return (0, 0) }

        var start = 0
        if let first = rows.first, let cell = first.first,
           cell.trimmingCharacters(in: .whitespaces).caseInsensitiveCompare("name") == .orderedSame {
            start = 1
        }

        var byName: [String: Member] = [:]
        for member in existing { byName[member.name.lowercased()] = member }

        var inserted = 0
        var updated = 0
        for row in rows[start...] {
            guard let rawName = row.first else { continue }
            let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
            if name.isEmpty { continue }
            let active = row.count > 1 ? parseBool(row[1]) : true
            let notes = row.count > 2 ? row[2] : ""
            let joined = row.count > 3 ? parseDate(row[3]) : nil

            if let member = byName[name.lowercased()] {
                member.isActive = active
                member.notes = notes
                if let joined { member.joinedDate = joined }  // keep existing if absent
                updated += 1
            } else {
                let member = Member(
                    name: name,
                    isActive: active,
                    notes: notes,
                    joinedDate: joined ?? Member.defaultJoinedDate
                )
                context.insert(member)
                byName[name.lowercased()] = member
                inserted += 1
            }
        }
        return (inserted, updated)
    }

    private static func parseBool(_ string: String) -> Bool {
        let value = string.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return ["yes", "y", "true", "1", "active", "x"].contains(value)
    }

    private static func parseDate(_ string: String) -> Date? {
        let value = string.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.isEmpty { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        for format in importDateFormats {
            formatter.dateFormat = format
            if let date = formatter.date(from: value) { return date }
        }
        return nil
    }

    private static func escape(_ field: String) -> String {
        if field.contains(",") || field.contains("\"") || field.contains("\n") || field.contains("\r") {
            return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return field
    }

    /// Minimal RFC-4180 CSV parser: handles quoted fields containing commas,
    /// escaped quotes (`""`), and newlines inside quotes.
    static func parse(_ text: String) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var inQuotes = false
        let chars = Array(text)
        var i = 0

        func endField() { row.append(field); field = "" }
        func endRow() { endField(); rows.append(row); row = [] }

        while i < chars.count {
            let c = chars[i]
            if inQuotes {
                if c == "\"" {
                    if i + 1 < chars.count, chars[i + 1] == "\"" {
                        field.append("\"")
                        i += 2
                    } else {
                        inQuotes = false
                        i += 1
                    }
                } else {
                    field.append(c)
                    i += 1
                }
            } else {
                switch c {
                case "\"":
                    inQuotes = true
                    i += 1
                case ",":
                    endField()
                    i += 1
                case "\n":
                    endRow()
                    i += 1
                case "\r":
                    endRow()
                    i += 1
                    if i < chars.count, chars[i] == "\n" { i += 1 }
                default:
                    field.append(c)
                    i += 1
                }
            }
        }
        if !field.isEmpty || !row.isEmpty { endRow() }
        return rows
    }
}

/// Wraps CSV text so it can be written via SwiftUI's `.fileExporter`.
struct MembersCSVDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.commaSeparatedText, .plainText] }

    var text: String

    init(text: String) { self.text = text }

    init(configuration: ReadConfiguration) throws {
        if let data = configuration.file.regularFileContents {
            text = String(decoding: data, as: UTF8.self)
        } else {
            text = ""
        }
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}
