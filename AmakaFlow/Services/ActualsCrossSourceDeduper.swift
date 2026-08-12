//
//  ActualsCrossSourceDeduper.swift
//  AmakaFlow
//
//  AMA-2422: certain-tier Strava + Apple Health dedupe so sessions/hours count once.
//

import Foundation

enum ActualsCrossSourceDeduper {
    /// Collapse certain cross-provider duplicates into one card (watch/AH streams preferred).
    static func dedupeCards(
        _ cards: [ActualsTodayDemoCard],
        memory: ActualsMergeMemory = ActualsMergeMemory()
    ) -> [ActualsTodayDemoCard] {
        guard cards.count > 1 else { return cards }

        var remaining = cards
        var result: [ActualsTodayDemoCard] = []

        while let seed = remaining.first {
            remaining.removeFirst()
            guard let seedRecording = ActualsCrossSourceDeduperSupport.recording(from: seed) else {
                result.append(seed)
                continue
            }

            var clusterCards = [seed]
            var clusterRecordings = [seedRecording]
            var providers: Set<ActualsSourceProvider> = [seedRecording.provider]

            var index = 0
            while index < remaining.count {
                let candidate = remaining[index]
                guard let candidateRecording = ActualsCrossSourceDeduperSupport.recording(from: candidate) else {
                    index += 1
                    continue
                }
                guard !providers.contains(candidateRecording.provider) else {
                    index += 1
                    continue
                }
                let isCertain = clusterRecordings.contains {
                    ActualsMergeClassifier.classify($0, candidateRecording, memory: memory) == .certain
                }
                guard isCertain else {
                    index += 1
                    continue
                }
                clusterCards.append(candidate)
                clusterRecordings.append(candidateRecording)
                providers.insert(candidateRecording.provider)
                remaining.remove(at: index)
            }

            if clusterCards.count == 1 {
                result.append(seed)
            } else {
                result.append(
                    ActualsCrossSourceDeduperSupport.mergeCards(clusterCards, recordings: clusterRecordings)
                )
            }
        }

        return result.sorted {
            ActualsCrossSourceDeduperSupport.startDate(of: $0) > ActualsCrossSourceDeduperSupport.startDate(of: $1)
        }
    }

    /// Collapse certain cross-provider duplicates for Profile aggregates / This week.
    static func dedupeCompletions(
        _ completions: [WorkoutCompletion],
        memory: ActualsMergeMemory = ActualsMergeMemory()
    ) -> [WorkoutCompletion] {
        guard completions.count > 1 else { return completions }

        var remaining = completions
        var result: [WorkoutCompletion] = []

        while let seed = remaining.first {
            remaining.removeFirst()
            let seedRecording = ActualsCrossSourceDeduperSupport.recording(from: seed)
            var cluster = [seed]
            var clusterRecordings = [seedRecording]
            var providers: Set<ActualsSourceProvider> = [seedRecording.provider]

            var index = 0
            while index < remaining.count {
                let candidate = remaining[index]
                let candidateRecording = ActualsCrossSourceDeduperSupport.recording(from: candidate)
                guard !providers.contains(candidateRecording.provider) else {
                    index += 1
                    continue
                }
                let isCertain = clusterRecordings.contains {
                    ActualsMergeClassifier.classify($0, candidateRecording, memory: memory) == .certain
                }
                guard isCertain else {
                    index += 1
                    continue
                }
                cluster.append(candidate)
                clusterRecordings.append(candidateRecording)
                providers.insert(candidateRecording.provider)
                remaining.remove(at: index)
            }

            if cluster.count == 1 {
                result.append(seed)
            } else {
                result.append(
                    ActualsCrossSourceDeduperSupport.mergeCompletions(cluster, recordings: clusterRecordings)
                )
            }
        }

        return result.sorted { $0.startedAt > $1.startedAt }
    }
}

// MARK: - Merge helpers (separate type keeps type_body_length under the CI cap)

private enum ActualsCrossSourceDeduperSupport {
    static func recording(from card: ActualsTodayDemoCard) -> ActualsSourceRecording? {
        if let primary = card.session?.primaryRecording {
            return primary
        }
        guard let activity = card.activity else { return nil }
        let provider = card.sourceProvider ?? activity.provider
        return ActualsSourceRecording(
            id: card.id,
            provider: provider,
            deviceKind: deviceKind(for: provider),
            title: card.title,
            startDate: activity.startDate,
            durationSeconds: activity.durationSeconds,
            distanceMeters: activity.distanceMeters,
            streamRichness: streamRichness(for: card)
        )
    }

    static func mergeCards(
        _ cards: [ActualsTodayDemoCard],
        recordings: [ActualsSourceRecording]
    ) -> ActualsTodayDemoCard {
        let session = ActualsMergeClassifier.merge(recordings)
        let stravaCard = cards.first { ($0.sourceProvider ?? $0.activity?.provider) == .strava }
        let appleCard = cards.first { ($0.sourceProvider ?? $0.activity?.provider) == .appleHealth }
        let verifiedCard = cards.first { $0.kind == .verified }

        let cardID = stravaCard?.id
            ?? session.primaryRecording?.id
            ?? cards[0].id
        let title = preferredTitle(from: cards.map(\.title))
        let activity = mergedActivity(
            strava: stravaCard?.activity,
            apple: appleCard?.activity,
            title: title,
            primaryProvider: session.primaryRecording?.provider ?? .appleHealth
        )
        let stats = mergedStats(from: cards, activity: activity)
        let timeLabel = stravaCard?.timeLabel
            ?? appleCard?.timeLabel
            ?? cards[0].timeLabel

        if let verifiedCard {
            return ActualsTodayDemoCard(
                id: cardID,
                kind: .verified,
                timeLabel: timeLabel,
                title: title,
                stats: stats,
                sourceLabel: verifiedCard.sourceLabel,
                sourceProvider: .strava,
                session: session,
                activity: activity ?? verifiedCard.activity,
                fillInSession: verifiedCard.fillInSession,
                stravaDecoration: stravaCard?.stravaDecoration ?? verifiedCard.stravaDecoration
            )
        }

        return ActualsTodayDemoCard(
            id: cardID,
            kind: .merged,
            timeLabel: timeLabel,
            title: title,
            stats: stats,
            sourceLabel: session.mergeBadge,
            sourceProvider: session.primaryRecording?.provider ?? .appleHealth,
            session: session,
            activity: activity,
            fillInSession: nil,
            stravaDecoration: stravaCard?.stravaDecoration ?? .none
        )
    }

    static func mergedActivity(
        strava: ActualsUnmappedActivity?,
        apple: ActualsUnmappedActivity?,
        title: String,
        primaryProvider: ActualsSourceProvider
    ) -> ActualsUnmappedActivity? {
        guard let base = strava ?? apple else { return nil }
        let start = strava?.startDate ?? apple?.startDate ?? base.startDate
        let duration = max(strava?.durationSeconds ?? 0, apple?.durationSeconds ?? 0)
        return ActualsUnmappedActivity(
            title: title,
            provider: primaryProvider,
            startDate: start,
            durationSeconds: duration > 0 ? duration : base.durationSeconds,
            distanceMeters: strava?.distanceMeters ?? apple?.distanceMeters,
            calories: apple?.calories ?? strava?.calories,
            avgHR: apple?.avgHR ?? strava?.avgHR,
            type: strava?.type ?? apple?.type ?? .other,
            stravaTypeRaw: strava?.stravaTypeRaw,
            activityDescription: strava?.activityDescription ?? "",
            recordingApp: strava?.recordingApp ?? apple?.recordingApp,
            isRace: strava?.isRace ?? false
        )
    }

    static func mergedStats(
        from cards: [ActualsTodayDemoCard],
        activity: ActualsUnmappedActivity?
    ) -> [(icon: String, value: String)] {
        let minutes: Int = {
            if let duration = activity?.durationSeconds {
                return max(1, Int((duration / 60).rounded()))
            }
            return cards.compactMap { card -> Int? in
                guard let raw = card.stats.first(where: { $0.icon == "clock" })?.value else {
                    return nil
                }
                return Int(raw.filter(\.isNumber))
            }.max() ?? 1
        }()
        var stats: [(icon: String, value: String)] = [("clock", "\(minutes)m")]
        if let distanceMeters = activity?.distanceMeters, distanceMeters > 0 {
            let kilometers = distanceMeters / 1_000
            let distanceText = kilometers >= 10
                ? String(format: "%.0f km", kilometers)
                : String(format: "%.1f km", kilometers)
            stats.append(("figure.run", distanceText))
        }
        if let kcal = activity?.calories {
            stats.append(("flame.fill", "\(Int(kcal.rounded())) kcal"))
        }
        if let avgHR = activity?.avgHR {
            stats.append(("heart.fill", "\(Int(avgHR.rounded())) bpm"))
        }
        return stats
    }

    static func streamRichness(for card: ActualsTodayDemoCard) -> Int {
        var score = 0
        if card.activity?.avgHR != nil { score += 3 }
        if card.activity?.calories != nil { score += 2 }
        if card.activity?.distanceMeters != nil { score += 1 }
        if card.sourceProvider == .appleHealth { score += 1 }
        if card.kind == .verified { score += 1 }
        return score
    }

    static func startDate(of card: ActualsTodayDemoCard) -> Date {
        card.activity?.startDate
            ?? card.session?.primaryRecording?.startDate
            ?? .distantPast
    }

    static func recording(from completion: WorkoutCompletion) -> ActualsSourceRecording {
        let provider = provider(for: completion)
        var richness = 0
        if completion.avgHeartRate != nil { richness += 3 }
        if completion.activeCalories != nil { richness += 2 }
        if completion.distanceMeters != nil { richness += 1 }
        if provider == .appleHealth { richness += 1 }
        return ActualsSourceRecording(
            id: completion.id,
            provider: provider,
            deviceKind: deviceKind(for: provider),
            title: completion.workoutName,
            startDate: completion.startedAt,
            durationSeconds: TimeInterval(completion.durationSeconds),
            distanceMeters: completion.distanceMeters.map(Double.init),
            streamRichness: richness
        )
    }

    static func provider(for completion: WorkoutCompletion) -> ActualsSourceProvider {
        if completion.id.hasPrefix("strava_") { return .strava }
        if completion.id.hasPrefix("applehealth_") { return .appleHealth }
        if completion.source == .appleWatch { return .appleHealth }
        if completion.isSyncedToStrava { return .strava }
        return .appleHealth
    }

    static func mergeCompletions(
        _ completions: [WorkoutCompletion],
        recordings: [ActualsSourceRecording]
    ) -> WorkoutCompletion {
        let session = ActualsMergeClassifier.merge(recordings)
        let strava = completions.first { provider(for: $0) == .strava }
        let apple = completions.first { provider(for: $0) == .appleHealth }
        let primary = session.primaryRecording
        let startedAt = primary?.startDate
            ?? completions.map(\.startedAt).min()
            ?? completions[0].startedAt
        let durationSeconds = Int(
            (primary?.durationSeconds
                ?? TimeInterval(completions.map(\.durationSeconds).max() ?? 0)).rounded()
        )
        let hasApple = apple != nil
        return WorkoutCompletion(
            id: strava?.id ?? primary?.id ?? completions[0].id,
            workoutName: preferredTitle(from: completions.map(\.workoutName)),
            startedAt: startedAt,
            endedAt: startedAt.addingTimeInterval(TimeInterval(durationSeconds)),
            durationSeconds: durationSeconds,
            avgHeartRate: apple?.avgHeartRate ?? strava?.avgHeartRate,
            maxHeartRate: apple?.maxHeartRate ?? strava?.maxHeartRate,
            activeCalories: apple?.activeCalories ?? strava?.activeCalories,
            distanceMeters: strava?.distanceMeters ?? apple?.distanceMeters,
            source: hasApple ? .appleWatch : (strava?.source ?? .manual),
            syncedToStrava: completions.contains(where: \.isSyncedToStrava),
            workoutId: strava?.workoutId ?? apple?.workoutId,
            originalWorkout: strava?.originalWorkout ?? apple?.originalWorkout,
            isSimulated: false
        )
    }

    static func deviceKind(for provider: ActualsSourceProvider) -> ActualsDeviceKind {
        switch provider {
        case .appleHealth, .garmin: return .watch
        case .strava: return .phone
        }
    }

    static func preferredTitle(from titles: [String]) -> String {
        let trimmed = titles.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !trimmed.isEmpty else { return "Session" }
        let nonGeneric = trimmed.filter { !isGenericTitle($0) }
        let pool = nonGeneric.isEmpty ? trimmed : nonGeneric
        return pool.max(by: { $0.count < $1.count }) ?? pool[0]
    }

    static func isGenericTitle(_ title: String) -> Bool {
        let lowered = title.lowercased()
        return lowered == "workout" || lowered == "session"
    }
}
