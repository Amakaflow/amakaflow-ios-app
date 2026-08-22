// Reads one JSON record per line on stdin — {"name":…,"argv":[…],"defaults":{…},"env":{…}} —
// and prints the LaunchConfig it decodes to as canonical JSON. Linked against a
// real LaunchConfig.swift, so the differential compares the shipping decoder
// rather than a reimplementation of it.
import Foundation

struct StubDefaults: LaunchDefaultsReading {
    let values: [String: String]
    func string(forKey key: String) -> String? { values[key] }
}

func canonical(_ config: LaunchConfig?) -> String {
    guard let config else { return "null" }
    var parts: [String] = []
    parts.append("useFixtures=\(config.useFixtures)")
    parts.append("skipOnboarding=\(config.skipOnboarding)")
    parts.append("skipAppleWatch=\(config.skipAppleWatch)")
    parts.append("session=\(describe(config.session))")
    parts.append("clerkTestUser=\(config.clerkTestUser)")
    parts.append("fixtures=\(describe(config.fixtures))")
    parts.append("faults=[\(config.faults.map(describe).sorted().joined(separator: " "))]")
    parts.append("demoHost=\(describe(config.demoHost))")
    parts.append("actualsTodayDemo=\(config.actualsTodayDemo)")
    parts.append("simulationSpeed=\(config.simulationSpeed)")
    return parts.joined(separator: " ")
}

func describe(_ session: LaunchConfig.TestSession?) -> String {
    switch session {
    case .none: return "nil"
    case .legacyBoolean: return "legacyBoolean"
    case .identity(let userID, let email, let displayName):
        return "identity(\(userID ?? "-"),\(email),\(displayName ?? "-"))"
    case .realClerk(let email, let password):
        return "realClerk(\(email),\(password ?? "-"))"
    }
}

func describe(_ fixtures: LaunchConfig.FixtureSelection) -> String {
    switch fixtures {
    case .all: return "all"
    case .named(let names): return "named(\(names.joined(separator: "|")))"
    }
}

func describe(_ fault: LaunchConfig.FaultScenario) -> String {
    switch fault {
    case .emptyLibrary: return "emptyLibrary"
    case .libraryLoadFails: return "libraryLoadFails"
    case .garminPaired: return "garminPaired"
    case .garminPushFails(let reason): return "garminPushFails(\(reason))"
    case .watchItemReplaceFails: return "watchItemReplaceFails"
    case .watchItemReplaceSlow(let ms): return "watchItemReplaceSlow(\(ms))"
    case .watchManagerDemo: return "watchManagerDemo"
    }
}

func describe(_ host: LaunchConfig.DemoHost?) -> String {
    switch host {
    case .none: return "nil"
    case .createWithAIGenerating: return "createWithAIGenerating"
    case .actualsDogfood(let autorun): return "actualsDogfood(\(describe(autorun)))"
    }
}

func describe(_ mode: LaunchConfig.AutorunMode?) -> String {
    switch mode {
    case .none: return "-"
    case .live: return "live"
    case .companion: return "companion"
    case .fixture: return "fixture"
    case .walkthrough: return "walkthrough"
    }
}

while let line = readLine(strippingNewline: true) {
    guard !line.isEmpty, let data = line.data(using: .utf8),
          let record = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
    let name = record["name"] as? String ?? "?"
    let config = LaunchConfig.decode(
        argv: record["argv"] as? [String] ?? [],
        defaults: StubDefaults(values: record["defaults"] as? [String: String] ?? [:]),
        environment: record["env"] as? [String: String] ?? [:]
    )
    print("\(name)\t\(canonical(config))")
}
