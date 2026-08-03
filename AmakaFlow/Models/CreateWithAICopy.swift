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
        "Mobility and core to loosen up"
    ]
    static let draftBadge = "DRAFT · NOT SAVED"
    static let failureFinePrint =
        "If it fails you'll see exactly why — we never swap in a canned workout."
    static let refineApplying = "applying…"
    static let rateLimited =
        "You’re refining too quickly. Wait a moment, then try again."
    static let noWearableNote = "No wearable data used — based on your ask and available context."
    static let editAsk = "Edit ask"
    static let saveToLibrary = "Save to Library"
    static let startCTA = "Start"
    static let suggestAnother = "Suggest another"
    static let whyThisHeading = "WHY THIS"
    static let refineHeading = "REFINE"
    static let refinePlaceholder = "Tweak it — \"swap dips for push-ups\""
    static let refineAppliedSuffix = " — applied"
    static let usuallyUnder = "USUALLY UNDER 20S"
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
    typealias CoachingProfile = Components.Schemas.CoachingProfile
    private static let notesLimit = 1_000
    private static let separator = "\n\n"

    struct ComposedNotes {
        let notes: String
        let includedTweaks: [String]
    }

    /// Result of compose-time context chip discovery.
    struct ContextDiscovery {
        var attached: Set<CreateWithAIContextChip>
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

    static func chips(from flags: IncludeContext) -> Set<CreateWithAIContextChip> {
        var result = Set<CreateWithAIContextChip>()
        if flags.gym == true { result.insert(.gym) }
        if flags.profile == true { result.insert(.profile) }
        if flags.memories == true { result.insert(.memories) }
        return result
    }

    /// True when profile carries owned equipment the gym gate should surface.
    static func profileOffersEquipment(_ profile: CoachingProfile) -> Bool {
        guard let inventory = profile.equipment else { return false }
        let categories = [
            inventory.strength?.additionalProperties,
            inventory.cardio?.additionalProperties,
            inventory.bodyweight?.additionalProperties,
            inventory.mobility?.additionalProperties
        ]
        return categories.contains { dict in
            dict?.values.contains(true) == true
        }
    }

    /// Pure discovery used by compose. Callers supply probe outcomes so UI and
    /// tests share one honesty rule: probe failure defaults that chip attached
    /// (never all-false from a transient network blip).
    static func discoverContext(
        hasActiveGym: Bool,
        profile: Result<CoachingProfile?, Error>,
        memories: Result<[CoachMemory], Error>
    ) -> ContextDiscovery {
        var attached = Set<CreateWithAIContextChip>()

        if hasActiveGym {
            attached.insert(.gym)
        }

        switch profile {
        case .success(let value):
            if let value {
                attached.insert(.profile)
                if profileOffersEquipment(value) {
                    attached.insert(.gym)
                }
            }
        case .failure:
            attached.insert(.profile)
        }

        switch memories {
        case .success(let value):
            if !value.isEmpty {
                attached.insert(.memories)
            }
        case .failure:
            attached.insert(.memories)
        }

        return ContextDiscovery(attached: attached)
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
                notes: cappedToNotesLimit(trimmedAsk),
                includedTweaks: []
            )
        }

        var newestTweaks: [String] = []
        var tweaksLength = 0
        for tweak in trimmedTweaks.reversed() {
            let separatorLength = newestTweaks.isEmpty ? 0 : scalarCount(separator)
            let tweakLength = scalarCount(tweak)
            guard tweaksLength + separatorLength + tweakLength <= notesLimit else {
                break
            }
            newestTweaks.append(tweak)
            tweaksLength += separatorLength + tweakLength
        }
        newestTweaks.reverse()

        if newestTweaks.isEmpty, let newest = trimmedTweaks.last {
            let cappedNewest = cappedToNotesLimit(newest)
            return ComposedNotes(notes: cappedNewest, includedTweaks: [cappedNewest])
        }

        let tweaksText = newestTweaks.joined(separator: separator)
        let askSeparatorLength = trimmedAsk.isEmpty ? 0 : scalarCount(separator)
        let askBudget = max(0, notesLimit - scalarCount(tweaksText) - askSeparatorLength)
        let askHead = capped(trimmedAsk, maxScalars: askBudget)
        let notes = [askHead, tweaksText]
            .filter { !$0.isEmpty }
            .joined(separator: separator)
        return ComposedNotes(notes: notes, includedTweaks: newestTweaks)
    }

    /// Cap by Unicode scalar count to match Pydantic `max_length` (code points).
    static func cappedToNotesLimit(_ string: String) -> String {
        capped(string, maxScalars: notesLimit)
    }

    private static func scalarCount(_ string: String) -> Int {
        string.unicodeScalars.count
    }

    private static func capped(_ string: String, maxScalars: Int) -> String {
        guard maxScalars >= 0 else { return "" }
        let scalars = string.unicodeScalars
        guard scalars.count > maxScalars else { return string }
        let end = scalars.index(scalars.startIndex, offsetBy: maxScalars)
        return String(String.UnicodeScalarView(scalars[..<end]))
    }
}
