//
//  CreateWithAICopy.swift
//  AmakaFlow
//
//  Shared product copy for the Create with AI flow.
//

import Foundation

enum CreateWithAICopy {
    static let composeTitle = "What do you want to do?"
    static let composeSubtitle = "Tell your coach what kind of session you want."
    static let starters = [
        "A 30-minute full-body strength session",
        "An easy run with a strong finish",
        "A low-impact workout for a busy day",
        "Mobility and core to loosen up",
    ]
    static let draftBadge = "DRAFT · NOT SAVED"
    static let failureFinePrint =
        "If it fails you'll see exactly why — we never swap in a canned workout."
    static let refineApplying = "applying…"
    static let rateLimited =
        "You’re refining too quickly. Wait a moment, then try again."
}

enum CreateWithAIContextChip: String, CaseIterable, Hashable, Identifiable {
    case gym
    case profile
    case memories

    var id: String { rawValue }

    var label: String {
        switch self {
        case .gym: return "Gym + equipment"
        case .profile: return "Training profile"
        case .memories: return "Coach memories"
        }
    }

    var icon: String {
        switch self {
        case .gym: return "dumbbell.fill"
        case .profile: return "person.crop.circle.fill"
        case .memories: return "brain.head.profile"
        }
    }
}

enum CreateWithAIPromptBuilder {
    typealias IncludeContext = Components.Schemas.IncludeContextFlags

    static func includeContext(
        attached: Set<CreateWithAIContextChip>
    ) -> IncludeContext {
        IncludeContext(
            gym: attached.contains(.gym),
            history: false,
            memories: attached.contains(.memories),
            profile: attached.contains(.profile),
            readiness: false
        )
    }

    static func composeNotes(ask: String, tweaks: [String] = []) -> String {
        let trimmedAsk = ask.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedTweaks = tweaks
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let composed = ([trimmedAsk] + trimmedTweaks).filter { !$0.isEmpty }.joined(separator: "\n\n")
        return String(composed.prefix(1_000))
    }
}
