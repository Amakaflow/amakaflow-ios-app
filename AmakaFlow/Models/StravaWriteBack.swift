//
//  StravaWriteBack.swift
//  AmakaFlow
//
//  AMA-2396: signed Strava write-back ownership marker, skip rules, and
//  per-session decoration state. Protocol seam mirrors StubActualsProviderAuth.
//

import Combine
import Foundation

/// Single shared ownership marker — write AND detection use this exact string.
enum StravaWriteBackSignature {
    static let line = "— tracked with AmakaFlow"
}

/// Per-session write-state surfaced as `SZStravaBadge` (rig panels 3–4).
enum StravaDecorationState: Equatable, Hashable, Codable, Sendable {
    case ours
    case skipped(rule: StravaWriteBackSkipRule)
    case untouched
    /// Never written / no Strava involvement.
    case none

    var badgeLabel: String? {
        switch self {
        case .ours: return "STRAVA ✓ OURS"
        case .skipped: return "STRAVA · SKIPPED"
        case .untouched: return "STRAVA · UNTOUCHED"
        case .none: return nil
        }
    }

    /// Prototype `state` key: ours / skipped / theirs / null.
    var prototypeKey: String? {
        switch self {
        case .ours: return "ours"
        case .skipped: return "skipped"
        case .untouched: return "theirs"
        case .none: return nil
        }
    }
}

extension StravaDecorationState {
    /// Compact string for local persistence (`actuals_sessions.strava_decoration`).
    var persistedRawValue: String? {
        switch self {
        case .ours: return "ours"
        case .skipped(let rule): return "skipped:\(rule.rawValue)"
        case .untouched: return "untouched"
        case .none: return nil
        }
    }

    init(persistedRawValue: String?) {
        guard let raw = persistedRawValue, !raw.isEmpty else {
            self = .none
            return
        }
        if raw == "ours" {
            self = .ours
            return
        }
        if raw == "untouched" {
            self = .untouched
            return
        }
        if raw.hasPrefix("skipped:"),
           let rule = StravaWriteBackSkipRule(rawValue: String(raw.dropFirst("skipped:".count))) {
            self = .skipped(rule: rule)
            return
        }
        self = .none
    }
}

enum StravaWriteBackSkipRule: String, Equatable, Hashable, Codable, CaseIterable, Sendable {
    case virtual
    case described
    case race

    var title: String {
        switch self {
        case .virtual: return "Virtual rides & runs"
        case .described: return "Anything someone else described"
        case .race: return "Races"
        }
    }

    var subtitle: String {
        switch self {
        case .virtual:
            return "ZWIFT · TRAINERROAD · MYWHOOSH — THEIR APPS WRITE RICH DETAIL"
        case .described:
            return "WORDS WITHOUT OUR SIGNATURE = NOT OURS — NEVER OVERWRITTEN. OUR OWN UPDATES ARE SIGNED, SO WE CAN REFRESH THEM."
        case .race:
            return "ACTIVITIES TAGGED AS A RACE ON STRAVA"
        }
    }
}

struct StravaWriteBackRules: Equatable, Codable, Sendable {
    var skipVirtual: Bool
    var skipDescribed: Bool
    var skipRaces: Bool

    static let `default` = StravaWriteBackRules(
        skipVirtual: true,
        skipDescribed: true,
        skipRaces: false
    )
}

struct StravaPreUpdateSnapshot: Equatable, Codable, Sendable {
    var activityId: String
    var preUpdateTitle: String
    var preUpdateDescription: String
    var rev: Int
}

struct StravaWriteBackDecision: Equatable, Sendable {
    var shouldWrite: Bool
    var state: StravaDecorationState
    var decoratedDescription: String?
}

enum StravaWriteBackDecorator {
    /// Append the ownership signature. Decorating twice is byte-identical
    /// (matches backend `decorate_description`).
    static func decorate(description: String) -> String {
        if containsOurSignature(description) { return description }
        let base = description
        if base.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return StravaWriteBackSignature.line
        }
        return "\(base)\n\n\(StravaWriteBackSignature.line)"
    }

    /// Preview card body: structure summary + signature on the last line.
    static func previewDescription(structureBody: String, rpe: Int?) -> String {
        var lines: [String] = []
        let trimmed = structureBody.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { lines.append(trimmed) }
        if let rpe {
            lines.append("RPE \(rpe) \(StravaWriteBackSignature.line)")
        } else {
            lines.append(StravaWriteBackSignature.line)
        }
        return lines.joined(separator: "\n")
    }

    /// Refresh our signed text in place (edit actuals). One signature always.
    static func refreshOurs(
        existingDescription: String,
        structureBody: String,
        rpe: Int?
    ) -> String {
        let fresh = previewDescription(structureBody: structureBody, rpe: rpe)
        if !containsOurSignature(existingDescription) {
            return decorate(description: fresh)
        }
        // Drop everything from the first signature-bearing block onward and replace.
        if let range = existingDescription.range(of: StravaWriteBackSignature.line) {
            var prefix = String(existingDescription[..<range.lowerBound])
            if let sep = prefix.range(of: "\n\n", options: .backwards) {
                prefix = String(prefix[..<sep.lowerBound])
            }
            // Also strip a trailing "RPE N — tracked…" line if it sits alone after a newline.
            while prefix.hasSuffix("\n") { prefix.removeLast() }
            // Remove a trailing RPE line that preceded the signature on the same line path.
            let parts = prefix.components(separatedBy: "\n")
            var kept = parts
            if let last = kept.last,
               last.uppercased().hasPrefix("RPE ") {
                kept.removeLast()
            }
            // Structure body may have been our previous preview — replace whole ours section.
            let rebuilt = previewDescription(structureBody: structureBody, rpe: rpe)
            let head = kept.joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if head.isEmpty { return rebuilt }
            return "\(head)\n\n\(rebuilt)"
        }
        return fresh
    }

    static func containsOurSignature(_ description: String) -> Bool {
        description.contains(StravaWriteBackSignature.line)
    }

    static func evaluate(
        activityType: String,
        recordingApp: String?,
        description: String,
        isRace: Bool,
        rules: StravaWriteBackRules,
        structureBody: String,
        rpe: Int? = nil
    ) -> StravaWriteBackDecision {
        let typeLower = activityType.lowercased()
        let appLower = (recordingApp ?? "").lowercased()
        let virtualTypes: Set<String> = ["virtualride", "virtualrun"]
        let virtualApps = ["zwift", "trainerroad", "mywhoosh", "peloton", "rouvy", "fulgaz", "kinomap"]

        if rules.skipVirtual {
            if virtualTypes.contains(typeLower)
                || virtualApps.contains(where: { appLower.contains($0) }) {
                return StravaWriteBackDecision(
                    shouldWrite: false,
                    state: .skipped(rule: .virtual),
                    decoratedDescription: nil
                )
            }
        }

        let trimmed = description.trimmingCharacters(in: .whitespacesAndNewlines)
        if rules.skipDescribed,
           !trimmed.isEmpty,
           !containsOurSignature(description) {
            return StravaWriteBackDecision(
                shouldWrite: false,
                state: .skipped(rule: .described),
                decoratedDescription: nil
            )
        }

        if rules.skipRaces, isRace {
            return StravaWriteBackDecision(
                shouldWrite: false,
                state: .skipped(rule: .race),
                decoratedDescription: nil
            )
        }

        let decorated: String
        if containsOurSignature(description) {
            decorated = refreshOurs(
                existingDescription: description,
                structureBody: structureBody,
                rpe: rpe
            )
        } else if structureBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            decorated = decorate(description: description)
        } else {
            decorated = previewDescription(structureBody: structureBody, rpe: rpe)
        }
        return StravaWriteBackDecision(
            shouldWrite: true,
            state: .ours,
            decoratedDescription: decorated
        )
    }
}

// MARK: - Settings store (local until BFF write-back settings are live)

@MainActor
final class StravaWriteBackSettingsStore: ObservableObject {
    private enum Keys {
        static let master = "ama2396.strava.writeBackEnabled"
        static let rules = "ama2396.strava.writeBackRules"
        static let hasWriteScope = "ama2396.strava.hasActivityWriteScope"
    }

    private let defaults: UserDefaults

    @Published var writeBackEnabled: Bool {
        didSet { defaults.set(writeBackEnabled, forKey: Keys.master) }
    }

    @Published var rules: StravaWriteBackRules {
        didSet {
            if let data = try? JSONEncoder().encode(rules) {
                defaults.set(data, forKey: Keys.rules)
            }
        }
    }

    @Published var hasActivityWriteScope: Bool {
        didSet { defaults.set(hasActivityWriteScope, forKey: Keys.hasWriteScope) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        writeBackEnabled = defaults.bool(forKey: Keys.master)
        hasActivityWriteScope = defaults.bool(forKey: Keys.hasWriteScope)
        if let data = defaults.data(forKey: Keys.rules),
           let decoded = try? JSONDecoder().decode(StravaWriteBackRules.self, from: data) {
            rules = decoded
        } else {
            rules = .default
        }
    }

    nonisolated deinit {}

    var statusLine: String {
        if writeBackEnabled, hasActivityWriteScope {
            return "CONNECTED ✓ · READ + WRITE-BACK"
        }
        return ActualsCopy.connectedBadge
    }
}

// MARK: - Write-back provider seam (StubActualsProviderAuth pattern)

enum StravaWriteBackOutcome: Equatable, Sendable {
    case updated(title: String, description: String)
    case skipped(StravaDecorationState)
    case restored
    case failed(String)
    case cancelled
}

protocol StravaWriteBackProviding: AnyObject {
    func writeBack(
        activityId: String,
        title: String,
        structureBody: String,
        currentDescription: String,
        activityType: String,
        recordingApp: String?,
        isRace: Bool,
        rules: StravaWriteBackRules
    ) async -> StravaWriteBackOutcome

    func restore(
        activityId: String,
        snapshot: StravaPreUpdateSnapshot
    ) async -> StravaWriteBackOutcome
}

/// DEBUG success / Release fail — same spirit as StubActualsProviderAuth.
final class StubStravaWriteBackProvider: StravaWriteBackProviding {
    var nextOutcome: StravaWriteBackOutcome?
    private(set) var writeCalls = 0
    private(set) var restoreCalls = 0
    private var snapshots: [String: StravaPreUpdateSnapshot] = [:]

    func writeBack(
        activityId: String,
        title: String,
        structureBody: String,
        currentDescription: String,
        activityType: String,
        recordingApp: String?,
        isRace: Bool,
        rules: StravaWriteBackRules
    ) async -> StravaWriteBackOutcome {
        writeCalls += 1
        if let nextOutcome { return nextOutcome }
        #if DEBUG
        let decision = StravaWriteBackDecorator.evaluate(
            activityType: activityType,
            recordingApp: recordingApp,
            description: currentDescription,
            isRace: isRace,
            rules: rules,
            structureBody: structureBody,
            rpe: nil
        )
        guard decision.shouldWrite, let decorated = decision.decoratedDescription else {
            return .skipped(decision.state)
        }
        if snapshots[activityId] == nil {
            snapshots[activityId] = StravaPreUpdateSnapshot(
                activityId: activityId,
                preUpdateTitle: title,
                preUpdateDescription: currentDescription,
                rev: 1
            )
        } else if var existing = snapshots[activityId] {
            existing.rev += 1
            snapshots[activityId] = existing
        }
        return .updated(title: title, description: decorated)
        #else
        return .failed("Write-back unavailable")
        #endif
    }

    func restore(
        activityId: String,
        snapshot: StravaPreUpdateSnapshot
    ) async -> StravaWriteBackOutcome {
        restoreCalls += 1
        if let nextOutcome { return nextOutcome }
        #if DEBUG
        snapshots.removeValue(forKey: activityId)
        return .restored
        #else
        return .failed("Restore unavailable")
        #endif
    }
}

final class MockStravaWriteBackProvider: StravaWriteBackProviding {
    var writeHandler: ((String) -> StravaWriteBackOutcome)?
    var restoreHandler: ((StravaPreUpdateSnapshot) -> StravaWriteBackOutcome)?
    private(set) var writeCalls: [String] = []
    private(set) var restoreCalls: [String] = []

    func writeBack(
        activityId: String,
        title: String,
        structureBody: String,
        currentDescription: String,
        activityType: String,
        recordingApp: String?,
        isRace: Bool,
        rules: StravaWriteBackRules
    ) async -> StravaWriteBackOutcome {
        writeCalls.append(activityId)
        return writeHandler?(activityId) ?? .cancelled
    }

    func restore(
        activityId: String,
        snapshot: StravaPreUpdateSnapshot
    ) async -> StravaWriteBackOutcome {
        restoreCalls.append(activityId)
        return restoreHandler?(snapshot) ?? .cancelled
    }
}

enum StravaWriteBackFactory {
    static func makeDefault() -> any StravaWriteBackProviding {
        if ProcessInfo.processInfo.environment["UITEST_USE_FIXTURES"] == "1" {
            return StubStravaWriteBackProvider()
        }
        #if DEBUG
        return StubStravaWriteBackProvider()
        #else
        // Live BFF path lands with AMA-2391 write-back deploy; stub until then.
        return StubStravaWriteBackProvider()
        #endif
    }
}
