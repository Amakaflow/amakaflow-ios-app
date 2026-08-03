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
    private static let notesLimit = 1_000
    private static let separator = "\n\n"

    struct ComposedNotes {
        let notes: String
        let includedTweaks: [String]
    }

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
        compose(ask: ask, tweaks: tweaks).notes
    }

    static func compose(ask: String, tweaks: [String] = []) -> ComposedNotes {
        let trimmedAsk = ask.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedTweaks = tweaks
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !trimmedTweaks.isEmpty else {
            return ComposedNotes(
                notes: String(trimmedAsk.prefix(notesLimit)),
                includedTweaks: []
            )
        }

        var newestTweaks: [String] = []
        var tweaksLength = 0
        for tweak in trimmedTweaks.reversed() {
            let separatorLength = newestTweaks.isEmpty ? 0 : separator.count
            guard tweaksLength + separatorLength + tweak.count <= notesLimit else {
                break
            }
            newestTweaks.append(tweak)
            tweaksLength += separatorLength + tweak.count
        }
        newestTweaks.reverse()

        if newestTweaks.isEmpty, let newest = trimmedTweaks.last {
            let cappedNewest = String(newest.prefix(notesLimit))
            return ComposedNotes(notes: cappedNewest, includedTweaks: [cappedNewest])
        }

        let tweaksText = newestTweaks.joined(separator: separator)
        let askSeparatorLength = trimmedAsk.isEmpty ? 0 : separator.count
        let askBudget = max(0, notesLimit - tweaksText.count - askSeparatorLength)
        let askHead = String(trimmedAsk.prefix(askBudget))
        let notes = [askHead, tweaksText]
            .filter { !$0.isEmpty }
            .joined(separator: separator)
        return ComposedNotes(notes: notes, includedTweaks: newestTweaks)
    }
}
