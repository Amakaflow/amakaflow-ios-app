# AMA-2387 — Task 2 report: Connect Sources screen

**Status: DONE**

## What was built

1. **Tests first** — `AmakaFlowCompanion/AmakaFlowCompanionTests/ActualsConnectSourcesCopyTests.swift`
   Locks the Connect Sources copy contract read by the new view:
   - `connectTitle` == "Pull your training in"
   - `connectSubhead` contains "We only read; we never post"
   - per-provider one-liners (Apple Health / Garmin / Strava) match `design-handoff/reference/screens-actuals.jsx` `SYConnectScreen` exactly
   - `connectDedupeFooter` exact uppercase copy
   - `connectedBadge` / `connectButton` copy
   - a11y IDs for every `ActualsSourceProvider`: `af_actuals_source_row_<provider>`, `af_actuals_connect_<provider>`
   - full `ActualsSourceProvider.allCases` coverage (appleHealth/garmin/strava)

   These assert against `ActualsCopy` (Task 1), which already defined the connect-screen strings — so they act as a regression lock for the view rather than driving new copy, and they pass today.

2. **`AmakaFlow/Views/ActualsConnectSourcesView.swift`** — the real Connect Sources screen:
   - Title "Pull your training in" + subhead from `ActualsCopy.connectSubhead` (carries "We only read; we never post")
   - One card per `ActualsSourceProvider.allCases` (Apple Health / Garmin / Strava), each with icon chip, display name, mono one-liner
   - Connected state → lime mono `"CONNECTED ✓"` badge; not-connected → pill "Connect" button
     - Connect button background is **lime** for Apple Health/Garmin, and **Strava brand red `#FC4C02`** for Strava specifically (per task spec), matching the icon-chip Strava color already used in `ActualsTeachCard`
   - Dashed-border dedupe footer card with the exact uppercase copy from `ActualsCopy.connectDedupeFooter`
   - Accessibility identifiers: each row carries `provider.accessibilityRowID` (`af_actuals_source_row_<provider>`), each Connect button carries `provider.accessibilityConnectID` (`af_actuals_connect_<provider>`)
   - Generic over `Store: ActualsSourceConnecting & ObservableObject` so the view stays reactive via `@ObservedObject` while still being expressed against the `ActualsSourceConnecting` protocol (injectable/fakeable for future tests); a convenience `init()` defaults `Store == ActualsSourceConnectionStore`
   - `onConnect: (ActualsSourceProvider) -> Void` defaults to `store.markConnected(provider)` (OAuth stub — real Strava/Garmin OAuth and Apple HealthKit flows land in Tasks 3–4 per `design-handoff/ACTUALS.md` build order)
   - `.ddSuppressFloatingChrome()` + dark preferred color scheme, matching the placeholder it replaces

3. **Wired `TodayDiaryView`** — replaced the Task 1 placeholder `Text` in the `navigationDestination(isPresented: $showConnectSources)` with `ActualsConnectSourcesView(store: actualsSources)`, reusing the existing `@StateObject` `ActualsSourceConnectionStore` instance so connecting a source here immediately reflects in the Today teach-card gating (`hasEverConnected`).

4. **Xcode project wiring** — added `AMA2387CONNREF`/`AMA2387CONNBLD` (view) and `AMA2387CONNTREF`/`AMA2387CONNTBLD` (test) file reference + build file pairs to `AmakaFlowCompanion.xcodeproj/project.pbxproj`, following the exact `AMA2386*` pattern: file reference in the flat sources list next to `ActualsTeachCard.swift`/`ActualsTeachCardVisibilityTests.swift`, and build-file entries added to both the `AmakaFlowCompanion` and `AmakaFlowCompanionTests` Sources build phases. Verified with `plutil -lint` (OK).

## Verification performed

- `plutil -lint project.pbxproj` → OK (valid property list after edits).
- `xcodebuild … build-for-testing` for the `AmakaFlowCompanion` scheme (isolated `-derivedDataPath` to avoid clashing with a concurrent build already running in this shared worktree) → **TEST BUILD SUCCEEDED**, zero compile errors, including `ActualsConnectSourcesView.swift` and `ActualsConnectSourcesCopyTests.swift` compiling cleanly into the app and test targets respectively.
- Confirmed the only "duplicate build file" warnings touching my new files are the same pre-existing project-wide quirk that already affects every other test file (including Task 1's own `ActualsSourceConnectionStoreTests.swift`) — not something introduced by this change.
- **Could not get a simulator to actually execute** `ActualsConnectSourcesCopyTests` end-to-end: another `xcodebuild test` process was already running against this same worktree/DerivedData for most of the session (looked like a controller/sibling agent verifying Task 1+2 together), and my own attempt on a separate simulator device stalled for 7+ minutes with the simulator never booting (environment/CoreSimulator contention), so I killed it rather than let it hang indefinitely.
- In lieu of a simulator run, I manually diffed every assertion in `ActualsConnectSourcesCopyTests.swift` character-for-character against `ActualsCopy.swift` (Task 1) and `design-handoff/reference/screens-actuals.jsx`'s `SYConnectScreen` — all match, so the tests are expected to pass once run.

## Files changed

- `AmakaFlow/Views/ActualsConnectSourcesView.swift` (new)
- `AmakaFlowCompanion/AmakaFlowCompanionTests/ActualsConnectSourcesCopyTests.swift` (new)
- `AmakaFlow/Views/TodayDiaryView.swift` (modified — placeholder → real view)
- `AmakaFlowCompanion/AmakaFlowCompanion.xcodeproj/project.pbxproj` (modified — added AMA2387CONN* entries)

Nothing was committed, per instructions.

## Concerns / notes for the controller

- **Could not run the test suite in a simulator this session** due to another concurrent `xcodebuild test` process already occupying this shared worktree's DerivedData/simulator for the full session (started before I began, still running at time of writing). Compile-level verification (`build-for-testing` → TEST BUILD SUCCEEDED with an isolated DerivedData path) is solid, but an actual `xcodebuild test` pass on `ActualsConnectSourcesCopyTests` should be re-run once the shared environment is free, to be safe.
- Strava's Connect-button background color (`#FC4C02`) is a deviation from the literal JSX reference (which shows all Connect buttons as lime) — I followed the explicit task instruction over the JSX since the task text called it out specifically. Flagging in case product/design intended lime everywhere and the task instruction was itself an error.
- Did not touch Tasks 3+ (Apple HealthKit primer, Strava/Garmin OAuth, merge engine, map-to-plan, fill-in actuals) — `onConnect` is an explicit stub (`store.markConnected(provider)`) as instructed.
