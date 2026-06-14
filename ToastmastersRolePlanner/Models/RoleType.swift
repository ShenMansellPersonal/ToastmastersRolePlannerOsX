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
    case warmUp
    case grammarian
    case ahCounter
    case speaker
    case speakerIntroduction
    case speakerEvaluation
    case tableTopicsMaster
    case tableTopicsEvaluator
    case breakTime
    case generalEvaluatorFunctionary
    case generalEvaluatorEvaluations
    case timekeeper
    case presidentsClose

    var id: String { rawValue }

    /// Human-readable name for the role.
    var title: String {
        switch self {
        case .sergeantAtArms: "Sergeant at Arms"
        case .toastmaster: "Toastmaster"
        case .warmUp: "Warm Up"
        case .grammarian: "Grammarian"
        case .ahCounter: "Ah-Counter"
        case .speaker: "Speaker"
        case .speakerIntroduction: "Speaker Introduction"
        case .speakerEvaluation: "Speaker Evaluation"
        case .tableTopicsMaster: "Table Topics Master"
        case .tableTopicsEvaluator: "Table Topics Evaluator"
        case .breakTime: "Break"
        case .generalEvaluatorFunctionary: "General Evaluator – Functionary"
        case .generalEvaluatorEvaluations: "General Evaluator – Evaluations"
        case .timekeeper: "Timekeeper"
        case .presidentsClose: "President's Close"
        }
    }

    /// SF Symbol used in the UI for this role.
    var symbol: String {
        switch self {
        case .sergeantAtArms: "shield"
        case .toastmaster: "person.wave.2"
        case .warmUp: "flame"
        case .grammarian: "textformat.abc"
        case .ahCounter: "hand.raised"
        case .speaker: "mic"
        case .speakerIntroduction: "arrow.turn.down.right"
        case .speakerEvaluation: "arrow.turn.down.right"
        case .tableTopicsMaster: "bubble.left.and.bubble.right"
        case .tableTopicsEvaluator: "checkmark.bubble"
        case .breakTime: "cup.and.saucer"
        case .generalEvaluatorFunctionary: "list.clipboard"
        case .generalEvaluatorEvaluations: "star.bubble"
        case .timekeeper: "stopwatch"
        case .presidentsClose: "flag.checkered"
        }
    }

    /// Built-in default green / yellow / red signal times for the role.
    /// These seed the editable `RoleDefault` store on first launch.
    var defaultTiming: Timing {
        switch self {
        case .warmUp: Timing(green: 240, yellow: 300, red: 360)            // 4 / 5 / 6
        case .sergeantAtArms: Timing(green: 60, yellow: 90, red: 120)
        case .toastmaster: Timing(green: 60, yellow: 90, red: 120)
        case .grammarian: Timing(green: 60, yellow: 120, red: 180)
        case .ahCounter: Timing(green: 30, yellow: 60, red: 90)
        case .speaker: Timing(green: 300, yellow: 360, red: 420)           // 5 / 6 / 7
        case .speakerIntroduction: Timing(green: 30, yellow: 45, red: 60)
        case .speakerEvaluation: Timing(green: 120, yellow: 150, red: 180) // 2 / 2:30 / 3
        case .tableTopicsMaster: Timing(green: 60, yellow: 90, red: 120)
        case .tableTopicsEvaluator: Timing(green: 120, yellow: 150, red: 180)
        case .breakTime: Timing(green: 600, yellow: 660, red: 720)         // 10 / 11 / 12
        case .generalEvaluatorFunctionary: Timing(green: 60, yellow: 90, red: 120)
        case .generalEvaluatorEvaluations: Timing(green: 300, yellow: 360, red: 420)
        case .timekeeper: Timing(green: 60, yellow: 90, red: 120)
        case .presidentsClose: Timing(green: 60, yellow: 120, red: 180)
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
    /// A Speaker is added together with its Introduction (via "Add Speaker"),
    /// but the Speaker Evaluation is added separately so it can be placed later
    /// in the agenda, in the evaluation section.
    static var singleAddable: [RoleType] {
        [
            .sergeantAtArms,
            .toastmaster,
            .warmUp,
            .grammarian,
            .ahCounter,
            .tableTopicsMaster,
            .tableTopicsEvaluator,
            .speakerEvaluation,
            .breakTime,
            .generalEvaluatorFunctionary,
            .generalEvaluatorEvaluations,
            .timekeeper,
            .presidentsClose
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

    /// The introduction is indented under its speaker in lists. The evaluation
    /// is placed independently (later in the agenda), so it isn't indented.
    var isIndented: Bool {
        self == .speakerIntroduction
    }
}
