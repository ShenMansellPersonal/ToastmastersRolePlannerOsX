import Foundation

/// The built-in roles used to seed the `Role` catalogue on first launch.
///
/// At runtime the app reads the editable `Role` table — this enum is only the
/// bootstrap definition. Each case's `rawValue` becomes the seeded `Role.key`,
/// so templates and meetings created before roles became editable still resolve.
enum RoleType: String, CaseIterable {
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
    /// These seed the editable `Role` catalogue on first launch.
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
    /// Seeds `Role.allowsMultiple`.
    var allowsMultiple: Bool {
        switch self {
        case .speaker, .speakerIntroduction, .speakerEvaluation, .tableTopicsEvaluator:
            true
        default:
            false
        }
    }

    /// Whether the role is shown indented in lists (a speaker's introduction).
    /// Seeds `Role.isIndented`.
    var isIndented: Bool {
        self == .speakerIntroduction
    }
}
