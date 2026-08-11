//
//  StravaWriteBack.swift
//  AmakaFlow
//
//  AMA-2396: signed Strava write-back ownership marker, skip rules, and
//  per-session decoration state. Protocol seam mirrors StubActualsProviderAuth.
//

// swiftlint:disable file_length

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

/// Inputs for skip-rule evaluation + description decoration (keeps `evaluate` ≤5 params).
struct StravaWriteBackEvaluateInput: Equatable, Sendable {
    var activityType: String
    var recordingApp: String?
    var description: String
    var isRace: Bool
    var rules: StravaWriteBackRules
    var structureBody: String
    var rpe: Int?
}

/// Payload for a single Strava activity write-back attempt.
struct StravaWriteBackRequest: Equatable, Sendable {
    var activityId: String
    var title: String
    var structureBody: String
    var currentDescription: String
    var activityType: String
    var recordingApp: String?
    var isRace: Bool
    var rules: StravaWriteBackRules
    var rpe: Int?
    /// AMA-2403: AmakaFlow fill-in session id stored on the verified-session row.
    var amakaflowSessionId: String?
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
        if description.contains(StravaWriteBackSignature.line) { return true }
        // Tolerate older posts / ASCII hyphens / casing — "tracked with AmakaFlow"
        // in the Strava body means we already linked this activity.
        return description.range(
            of: "tracked with amakaflow",
            options: .caseInsensitive
        ) != nil
    }

    /// Pull `RPE N` from a signed Strava footer (`RPE 6 — tracked with AmakaFlow`).
    static func rpeFromSignedDescription(_ description: String) -> Int? {
        guard containsOurSignature(description) else { return nil }
        guard let regex = try? NSRegularExpression(
            pattern: #"RPE\s*(\d{1,2})"#,
            options: .caseInsensitive
        ) else { return nil }
        let nsDescription = description as NSString
        let matches = regex.matches(
            in: description,
            options: [],
            range: NSRange(location: 0, length: nsDescription.length)
        )
        guard let last = matches.last,
              last.numberOfRanges >= 2 else { return nil }
        let value = nsDescription.substring(with: last.range(at: 1))
        guard let rpe = Int(value), (1...10).contains(rpe) else { return nil }
        return rpe
    }

    static func evaluate(_ input: StravaWriteBackEvaluateInput) -> StravaWriteBackDecision {
        let typeLower = input.activityType.lowercased()
        let appLower = (input.recordingApp ?? "").lowercased()
        let virtualTypes: Set<String> = ["virtualride", "virtualrun"]
        let virtualApps = ["zwift", "trainerroad", "mywhoosh", "peloton", "rouvy", "fulgaz", "kinomap"]

        if input.rules.skipVirtual {
            if virtualTypes.contains(typeLower)
                || virtualApps.contains(where: { appLower.contains($0) }) {
                return StravaWriteBackDecision(
                    shouldWrite: false,
                    state: .skipped(rule: .virtual),
                    decoratedDescription: nil
                )
            }
        }

        let trimmed = input.description.trimmingCharacters(in: .whitespacesAndNewlines)
        if input.rules.skipDescribed,
           !trimmed.isEmpty,
           !containsOurSignature(input.description) {
            return StravaWriteBackDecision(
                shouldWrite: false,
                state: .skipped(rule: .described),
                decoratedDescription: nil
            )
        }

        if input.rules.skipRaces, input.isRace {
            return StravaWriteBackDecision(
                shouldWrite: false,
                state: .skipped(rule: .race),
                decoratedDescription: nil
            )
        }

        let decorated: String
        if containsOurSignature(input.description) {
            decorated = refreshOurs(
                existingDescription: input.description,
                structureBody: input.structureBody,
                rpe: input.rpe
            )
        } else if input.structureBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            decorated = decorate(description: input.description)
        } else {
            // Preserve a foreign body when skipDescribed is off — append our signed block.
            let ours = previewDescription(structureBody: input.structureBody, rpe: input.rpe)
            let existing = input.description.trimmingCharacters(in: .whitespacesAndNewlines)
            decorated = existing.isEmpty ? ours : "\(existing)\n\n\(ours)"
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
    /// Shared so Settings / Connect / Fill-in see the same toggle + write-scope flags.
    static let shared = StravaWriteBackSettingsStore()

    private enum Keys {
        /// UserDefaults key for the write-back toggle (stable string; do not rename).
        static let writeBackEnabled = "ama2396.strava.writeBackEnabled"
        static let rules = "ama2396.strava.writeBackRules"
        static let hasWriteScope = "ama2396.strava.hasActivityWriteScope"
    }

    private let defaults: UserDefaults

    @Published var writeBackEnabled: Bool {
        didSet { defaults.set(writeBackEnabled, forKey: Keys.writeBackEnabled) }
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
        writeBackEnabled = defaults.bool(forKey: Keys.writeBackEnabled)
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
            return ActualsCopy.writeBackStatusReadWrite
        }
        if hasActivityWriteScope {
            return "CONNECTED ✓ · WRITE READY · TOGGLE OFF"
        }
        return "CONNECTED ✓ · READ ONLY — RECONNECT FOR WRITE-BACK"
    }

    /// Call after a successful Strava OAuth that included `activity:write`.
    /// - Parameter grantedWrite: true when callback scope contains write, or when
    ///   this reconnect explicitly requested write and Strava returned success
    ///   (scope echo is empty on some redirect chains).
    func applyWriteGrantFromOAuth(grantedWrite: Bool) {
        guard grantedWrite else { return }
        hasActivityWriteScope = true
        writeBackEnabled = true
        defaults.set(true, forKey: Keys.hasWriteScope)
        defaults.set(true, forKey: Keys.writeBackEnabled)
        objectWillChange.send()
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
    func writeBack(_ request: StravaWriteBackRequest) async -> StravaWriteBackOutcome

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

    func writeBack(_ request: StravaWriteBackRequest) async -> StravaWriteBackOutcome {
        writeCalls += 1
        if let nextOutcome { return nextOutcome }
        #if DEBUG
        let decision = StravaWriteBackDecorator.evaluate(
            StravaWriteBackEvaluateInput(
                activityType: request.activityType,
                recordingApp: request.recordingApp,
                description: request.currentDescription,
                isRace: request.isRace,
                rules: request.rules,
                structureBody: request.structureBody,
                rpe: request.rpe
            )
        )
        guard decision.shouldWrite, let decorated = decision.decoratedDescription else {
            return .skipped(decision.state)
        }
        if snapshots[request.activityId] == nil {
            snapshots[request.activityId] = StravaPreUpdateSnapshot(
                activityId: request.activityId,
                preUpdateTitle: request.title,
                preUpdateDescription: request.currentDescription,
                rev: 1
            )
        } else if var existing = snapshots[request.activityId] {
            existing.rev += 1
            snapshots[request.activityId] = existing
        }
        return .updated(title: request.title, description: decorated)
        #else
        return .failed("Write-back unavailable")
        #endif
    }

    func restore(
        activityId: String,
        snapshot: StravaPreUpdateSnapshot
    ) async -> StravaWriteBackOutcome {
        restoreCalls += 1
        // Only honor explicit restore/fail stubs — never treat a write outcome as restore.
        if let nextOutcome {
            switch nextOutcome {
            case .restored, .failed, .cancelled:
                return nextOutcome
            case .updated, .skipped:
                break
            }
        }
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

    func writeBack(_ request: StravaWriteBackRequest) async -> StravaWriteBackOutcome {
        writeCalls.append(request.activityId)
        return writeHandler?(request.activityId) ?? .cancelled
    }

    func restore(
        activityId: String,
        snapshot: StravaPreUpdateSnapshot
    ) async -> StravaWriteBackOutcome {
        restoreCalls.append(activityId)
        return restoreHandler?(snapshot) ?? .cancelled
    }
}

/// Live write-back via mobile-BFF → strava-sync-api (AMA-2396).
final class BFFStravaWriteBackProvider: StravaWriteBackProviding {
    private let client: BFFStravaClient

    init(client: BFFStravaClient) {
        self.client = client
    }

    @MainActor
    static func live() -> BFFStravaWriteBackProvider {
        BFFStravaWriteBackProvider(client: .live())
    }

    func writeBack(_ request: StravaWriteBackRequest) async -> StravaWriteBackOutcome {
        // Client-side skip preview (same rules as stub) — avoids a network round
        // trip when we already know Strava must not be touched.
        let decision = StravaWriteBackDecorator.evaluate(
            StravaWriteBackEvaluateInput(
                activityType: request.activityType,
                recordingApp: request.recordingApp,
                description: request.currentDescription,
                isRace: request.isRace,
                rules: request.rules,
                structureBody: request.structureBody,
                rpe: request.rpe
            )
        )
        guard decision.shouldWrite else {
            return .skipped(decision.state)
        }
        let decorated = decision.decoratedDescription
            ?? StravaWriteBackDecorator.decorate(description: request.currentDescription)
        do {
            // AMA-2403: mark verified before apply so the AMA-2402 gate passes.
            // Best-effort: apply also marks when missing (TF ≤390 / older BFF).
            // Auth failures still abort so we don't mask reconnect needs.
            do {
                let verification = try await client.verifySession(
                    activityId: request.activityId,
                    amakaflowSessionId: request.amakaflowSessionId
                )
                guard verification.verified else {
                    return .failed(BFFStravaClientError.sessionNotVerified.localizedDescription)
                }
            } catch let error as BFFStravaClientError
                where error == .authenticationRequired || error == .sessionNotVerified {
                throw error
            } catch {
                // verify route lagging or transient — continue to apply
            }
            let result = try await client.applyWriteBack(
                activityId: request.activityId,
                title: request.title,
                description: decorated
            )
            if result.written {
                let writtenTitle = result.title.isEmpty ? request.title : result.title
                let writtenDescription = result.description.isEmpty ? decorated : result.description
                return .updated(title: writtenTitle, description: writtenDescription)
            }
            // Upstream skipped (virtual / described / race) after fetch.
            let state = Self.decoration(fromUpstreamStatus: result.status)
            return .skipped(state)
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    func restore(
        activityId: String,
        snapshot: StravaPreUpdateSnapshot
    ) async -> StravaWriteBackOutcome {
        _ = snapshot
        do {
            let result = try await client.restoreWriteBack(activityId: activityId)
            return result.restored ? .restored : .failed(result.message)
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    private static func decoration(fromUpstreamStatus status: String) -> StravaDecorationState {
        if status.contains("virtual") {
            return .skipped(rule: .virtual)
        }
        if status.contains("described") {
            return .skipped(rule: .described)
        }
        if status.contains("race") {
            return .skipped(rule: .race)
        }
        return .untouched
    }
}

enum StravaWriteBackFactory {
    @MainActor
    static func makeDefault() -> any StravaWriteBackProviding {
        if ProcessInfo.processInfo.environment["UITEST_USE_FIXTURES"] == "1" {
            return StubStravaWriteBackProvider()
        }
        #if DEBUG
        if ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1" {
            return StubStravaWriteBackProvider()
        }
        #endif
        return BFFStravaWriteBackProvider.live()
    }
}
