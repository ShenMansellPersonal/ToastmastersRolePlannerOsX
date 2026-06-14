import Foundation

/// The full set of roles that can appear on a Toastmasters meeting agenda.
///
/// A "Speaker" is special: each speaker on the agenda also needs an
/// Introduction and an Evaluation. Those are modelled as their own role
/// values (`speakerIntroduction` / `speakerEvaluation`) and grouped to a
/// speaker via `TemplateSlot.instanceNumber` / `RoleAssignment.instanceNumber`.
enum RoleType: String, Codable, CaseIterable, Identifiable {
    case sergeantAtArms
    case toastmaster
    case grammarian
    case ahCounter
    case speaker
    case speakerIntroduction
    case speakerEvaluation
    case tableTopicsMaster
    case tableTopicsEvaluator
    case generalEvaluatorFunctionary
    case generalEvaluatorEvaluations
    case timekeeper

    var id: String { rawValue }

    /// Human-readable name for the role.
    var title: String {
        switch self {
        case .sergeantAtArms: "Sergeant at Arms"
        case .toastmaster: "Toastmaster"
        case .grammarian: "Grammarian"
        case .ahCounter: "Ah-Counter"
        case .speaker: "Speaker"
        case .speakerIntroduction: "Speaker Introduction"
        case .speakerEvaluation: "Speaker Evaluation"
        case .tableTopicsMaster: "Table Topics Master"
        case .tableTopicsEvaluator: "Table Topics Evaluator"
        case .generalEvaluatorFunctionary: "General Evaluator – Functionary"
        case .generalEvaluatorEvaluations: "General Evaluator – Evaluations"
        case .timekeeper: "Timekeeper"
        }
    }

    /// SF Symbol used in the UI for this role.
    var symbol: String {
        switch self {
        case .sergeantAtArms: "shield"
        case .toastmaster: "person.wave.2"
        case .grammarian: "textformat.abc"
        case .ahCounter: "hand.raised"
        case .speaker: "mic"
        case .speakerIntroduction: "arrow.turn.down.right"
        case .speakerEvaluation: "arrow.turn.down.right"
        case .tableTopicsMaster: "bubble.left.and.bubble.right"
        case .tableTopicsEvaluator: "checkmark.bubble"
        case .generalEvaluatorFunctionary: "list.clipboard"
        case .generalEvaluatorEvaluations: "star.bubble"
        case .timekeeper: "stopwatch"
        }
    }

    /// Roles that may legitimately appear more than once on one agenda.
    var allowsMultiple: Bool {
        switch self {
        case .speaker, .speakerIntroduction, .speakerEvaluation, .tableTopicsEvaluator:
            true
        default:
            false
        }
    }

    /// Roles that are part of a speaker block (and therefore added together).
    var isSpeakerBlock: Bool {
        switch self {
        case .speaker, .speakerIntroduction, .speakerEvaluation: true
        default: false
        }
    }

    /// Roles offered as standalone choices in the "Add Role" menu.
    /// (Speakers are added as a block, so the sub-roles aren't listed here.)
    static var singleAddable: [RoleType] {
        [
            .sergeantAtArms,
            .toastmaster,
            .grammarian,
            .ahCounter,
            .tableTopicsMaster,
            .tableTopicsEvaluator,
            .generalEvaluatorFunctionary,
            .generalEvaluatorEvaluations,
            .timekeeper
        ]
    }

    /// A display label for a role given the instance it belongs to.
    /// `instance` is 0 for non-repeating roles.
    func label(instance: Int) -> String {
        switch self {
        case .speaker:
            return instance > 0 ? "Speaker #\(instance)" : "Speaker"
        case .speakerIntroduction:
            return instance > 0 ? "Introduction — Speaker #\(instance)" : "Speaker Introduction"
        case .speakerEvaluation:
            return instance > 0 ? "Evaluation — Speaker #\(instance)" : "Speaker Evaluation"
        case .tableTopicsEvaluator:
            return instance > 0 ? "Table Topics Evaluator #\(instance)" : title
        default:
            return title
        }
    }

    /// Sub-roles are indented under their parent speaker in lists.
    var isIndented: Bool {
        self == .speakerIntroduction || self == .speakerEvaluation
    }
}
