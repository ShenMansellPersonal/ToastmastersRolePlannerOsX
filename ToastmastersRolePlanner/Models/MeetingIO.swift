import Foundation
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// JSON import/export for meetings, including their role assignments
/// (member by name, any timing overrides) and absentees.
enum MeetingIO {
    struct File: Codable {
        var version = 1
        var meetings: [MeetingDTO]
    }

    struct MeetingDTO: Codable {
        var date: Date
        var theme: String
        var templateName: String
        var assignments: [AssignmentDTO]
        var absentees: [String]
    }

    struct AssignmentDTO: Codable {
        var roleKey: String
        /// Human-readable label; informational only on import.
        var roleLabel: String?
        var order: Int
        var instanceNumber: Int
        var customLabel: String
        var member: String?
        var green: Int?
        var yellow: Int?
        var red: Int?
    }

    private static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    // MARK: Export

    static func export(_ meetings: [Meeting], rolesByKey: [String: Role]) throws -> Data {
        let dtos = meetings.sorted { $0.date < $1.date }.map { meeting in
            MeetingDTO(
                date: meeting.date,
                theme: meeting.theme,
                templateName: meeting.templateName,
                assignments: meeting.orderedAssignments.map { assignment in
                    AssignmentDTO(
                        roleKey: assignment.roleRaw,
                        roleLabel: assignment.displayLabel(rolesByKey[assignment.roleRaw]),
                        order: assignment.order,
                        instanceNumber: assignment.instanceNumber,
                        customLabel: assignment.customLabel,
                        member: assignment.assigneeName,
                        green: assignment.overrideGreen,
                        yellow: assignment.overrideYellow,
                        red: assignment.overrideRed
                    )
                },
                absentees: meeting.absentees.map(\.name)
            )
        }
        return try encoder().encode(File(meetings: dtos))
    }

    // MARK: Import

    /// Decodes the file and inserts each meeting as a new record. Members are
    /// matched by name (case-insensitively); unmatched names are left
    /// unassigned. Returns how many meetings were imported.
    @discardableResult
    static func importing(_ data: Data, into context: ModelContext, members: [Member]) throws -> Int {
        let file = try decoder().decode(File.self, from: data)

        var byName: [String: Member] = [:]
        for member in members { byName[member.name.lowercased()] = member }
        func member(named name: String?) -> Member? {
            guard let name, !name.isEmpty else { return nil }
            return byName[name.lowercased()]
        }

        for dto in file.meetings {
            let meeting = Meeting(date: dto.date, theme: dto.theme, templateName: dto.templateName)
            meeting.assignments = dto.assignments.map { item in
                let matched = member(named: item.member)
                let assignment = RoleAssignment(
                    roleKey: item.roleKey,
                    order: item.order,
                    instanceNumber: item.instanceNumber,
                    customLabel: item.customLabel,
                    member: matched,
                    // Keep the original name even when it isn't a current member.
                    memberName: matched?.name ?? (item.member ?? "")
                )
                assignment.overrideGreen = item.green
                assignment.overrideYellow = item.yellow
                assignment.overrideRed = item.red
                return assignment
            }
            meeting.absentees = dto.absentees.compactMap { member(named: $0) }
            context.insert(meeting)
        }
        return file.meetings.count
    }
}

/// Wraps JSON data so it can be written via SwiftUI's `.fileExporter`.
struct MeetingsJSONDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }

    var data: Data

    init(data: Data) { self.data = data }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
