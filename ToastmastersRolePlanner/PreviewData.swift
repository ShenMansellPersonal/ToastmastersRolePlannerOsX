#if DEBUG
import Foundation
import SwiftData

/// Sample in-memory data for SwiftUI previews.
@MainActor
enum PreviewData {
    static let container: ModelContainer = {
        let schema = Schema([
            Member.self,
            MeetingTemplate.self,
            TemplateSlot.self,
            Meeting.self,
            RoleAssignment.self
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: schema, configurations: [configuration])
        seed(container.mainContext)
        return container
    }()

    static var sampleMeeting: Meeting {
        let descriptor = FetchDescriptor<Meeting>()
        return (try? container.mainContext.fetch(descriptor).first) ?? Meeting()
    }

    private static func seed(_ context: ModelContext) {
        let names = ["Alex Carter", "Bryn Davies", "Casey Wong", "Dana Patel", "Evan Ruiz", "Fiona Mak"]
        let members = names.map { Member(name: $0) }
        members.forEach { context.insert($0) }

        let template = MeetingTemplate(name: "Standard Agenda")
        context.insert(template)
        var order = 0
        func add(_ role: RoleType, instance: Int = 0) {
            template.slots.append(TemplateSlot(role: role, order: order, instanceNumber: instance))
            order += 1
        }
        add(.sergeantAtArms)
        add(.toastmaster)
        add(.grammarian)
        add(.ahCounter)
        add(.timekeeper)
        for speaker in 1...2 {
            add(.speaker, instance: speaker)
            add(.speakerIntroduction, instance: speaker)
            add(.speakerEvaluation, instance: speaker)
        }
        add(.tableTopicsMaster)
        add(.tableTopicsEvaluator, instance: 1)
        add(.tableTopicsEvaluator, instance: 2)
        add(.generalEvaluatorFunctionary)
        add(.generalEvaluatorEvaluations)

        let meeting = Meeting(date: Date(), theme: "Finding Your Voice")
        meeting.applyTemplate(template)
        context.insert(meeting)
        // Assign a few roles.
        for (index, assignment) in meeting.orderedAssignments.prefix(4).enumerated() {
            assignment.member = members[index % members.count]
        }
    }
}
#endif
