# AmakaFlow source folder

This folder contains the shared Swift source used by the checked-in Xcode project at `../AmakaFlowCompanion/AmakaFlowCompanion.xcodeproj`.

Do not create or expect an `AmakaFlow.xcodeproj` here. The current project lives under `AmakaFlowCompanion/` and references these files with sibling `../AmakaFlow/...` paths.

## Current source layout

```text
AmakaFlow/
├── Core/                  # App configuration, environment, feature flags, shared utilities
├── DependencyInjection/   # Runtime service/container wiring
├── Engine/                # Workout execution state and follow-along logic
├── Generated/             # Swift OpenAPI client/types generated from Specs/mobile-bff.json
├── LiveActivity/          # Live Activity shared code
├── Models/                # App/domain models
├── Resources/             # Fixtures and bundled resources
├── Services/              # API, auth, HealthKit, WatchConnectivity, imports, transcription
├── Simulation/            # Simulation helpers
├── Storage/               # GRDB migrations and repositories
├── ViewModels/            # Presentation logic
└── Views/                 # SwiftUI screens and reusable components
```

## Generated code

`Generated/Client.swift` and `Generated/Types.swift` are regenerated from the repo root:

```bash
./scripts/regen-openapi-client.sh
```

The source contract is `Specs/mobile-bff.json`; do not edit generated files directly.

## Adding files

When adding Swift files under this folder, also verify target membership in `AmakaFlowCompanion.xcodeproj` for the relevant iOS/watchOS/test target. Until the project layout is normalized, avoid moving this folder or the `.xcodeproj` independently.
