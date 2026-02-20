import Foundation
import WatchKit

struct FormResult {
    let label: String
    let confidence: Float
}

enum HapticCue: String, CaseIterable {
    case depthPrompt        // Single rising pulse — "go deeper"
    case stop               // Three sharp rapid taps — "rack it"
    case asymmetryWarning   // Double pulse — "check balance"
    case tempoTooFast       // Short staccato buzz — "slow down"
    case goodRep            // Single crisp tap — positive reinforcement
    case fatigueWarning     // Long fade-out pulse — "you're fading"
}

final class HapticCoach {
    private let confidenceThreshold: Float = 0.7

    init() {}

    func shouldCue(for result: FormResult) -> Bool {
        result.label != "good" && result.confidence >= confidenceThreshold
    }

    func cueType(for result: FormResult) -> HapticCue {
        switch result.label {
        case "insufficient_depth": return .depthPrompt
        case "knee_cave":          return .asymmetryWarning
        case "forward_lean":       return .tempoTooFast
        default:                   return .goodRep
        }
    }

    func play(_ cue: HapticCue) {
        DispatchQueue.main.async {
            switch cue {
            case .goodRep:
                WKInterfaceDevice.current().play(.success)
            case .stop:
                WKInterfaceDevice.current().play(.stop)
            case .depthPrompt, .asymmetryWarning, .tempoTooFast, .fatigueWarning:
                WKInterfaceDevice.current().play(.notification)
            }
        }
    }
}
