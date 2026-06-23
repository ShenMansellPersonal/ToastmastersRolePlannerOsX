import Foundation
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// JSON import/export for meeting templates (name, details, and ordered slots).
enum TemplateIO {
    struct File: Codable {
        var version = 1
        var templates: [TemplateDTO]
    }

    struct TemplateDTO: Codable {
        var name: String
        var details: String
        var slots: [SlotDTO]
    }

    struct SlotDTO: Codable {
        var roleKey: String
        var order: Int
        var instanceNumber: Int
        var customLabel: String
    }

    struct ImportResult {
        var inserted: Int
        var updated: Int
        var templates: [MeetingTemplate]
    }

    private static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return encoder
    }

    private static func decoder() -> JSONDecoder { JSONDecoder() }

    // MARK: Export

    static func export(_ templates: [MeetingTemplate]) throws -> Data {
        let dtos = templates
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            .map { template in
                TemplateDTO(
                    name: template.name,
                    details: template.details,
                    slots: template.orderedSlots.map {
                        SlotDTO(roleKey: $0.roleRaw, order: $0.order, instanceNumber: $0.instanceNumber, customLabel: $0.customLabel)
                    }
                )
            }
        return try encoder().encode(File(templates: dtos))
    }

    // MARK: Import

    /// Merges templates, matching existing ones by name (an exact match is
    /// updated in place, otherwise a new template is inserted).
    @discardableResult
    static func importing(_ data: Data, into context: ModelContext, existing: [MeetingTemplate]) throws -> ImportResult {
        let file = try decoder().decode(File.self, from: data)

        var byName: [String: MeetingTemplate] = [:]
        for template in existing { byName[template.name] = template }

        var touched: [MeetingTemplate] = []
        var inserted = 0
        var updated = 0

        for dto in file.templates {
            let template: MeetingTemplate
            if let match = byName[dto.name] {
                template = match
                updated += 1
            } else {
                template = MeetingTemplate(name: dto.name, details: dto.details)
                context.insert(template)
                byName[dto.name] = template
                inserted += 1
            }
            template.details = dto.details
            for slot in template.slots { context.delete(slot) }
            template.slots = dto.slots.map {
                TemplateSlot(roleKey: $0.roleKey, order: $0.order, instanceNumber: $0.instanceNumber, customLabel: $0.customLabel)
            }
            touched.append(template)
        }
        return ImportResult(inserted: inserted, updated: updated, templates: touched)
    }
}

/// Wraps JSON data for SwiftUI's `.fileExporter`.
struct TemplatesJSONDocument: FileDocument {
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
