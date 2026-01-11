# iOS CI Optimization Guide

This document describes the optimizations applied to the iOS CI workflow to reduce test runtime from 40+ minutes to ~15-20 minutes.

## Key Optimizations

### 1. Apple Silicon Runners (Biggest Win)

**Problem:** Standard macOS runners use older Intel hardware with limited resources, making Swift compilation and simulator booting slow.

**Solution:** Use Apple Silicon (M-series) XL runners:

```yaml
jobs:
  ios-tests:
    runs-on: macos-15-xlarge  # Apple Silicon M-series - 3-4x faster
```

**Impact:** ~50% reduction in build/test time. Costs more "minutes" per run but finishes 3-4x faster, often balancing out.

### 2. Cache Order (Critical)

**Problem:** SwiftPM packages were being resolved BEFORE cache restoration, making every build a cold cache.

**Solution:** Always restore caches BEFORE running `xcodebuild -resolvePackageDependencies`:

```yaml
# 1. Restore caches first
- name: Restore SwiftPM cache
  uses: actions/cache@v4
  with:
    path: AmakaFlowCompanion/.spm
    key: spm-${{ runner.os }}-${{ steps.xcode.outputs.version }}-${{ hashFiles(...) }}

- name: Restore DerivedData cache
  uses: actions/cache@v4
  with:
    path: AmakaFlowCompanion/DerivedData
    key: deriveddata-${{ runner.os }}-${{ steps.xcode.outputs.version }}-${{ hashFiles(...) }}

# 2. THEN resolve dependencies (will use cached .spm if available)
- name: Resolve SwiftPM dependencies
  run: xcodebuild -resolvePackageDependencies ...
```

### 3. Separate SwiftPM Cache Directory

**Problem:** Default SPM cache location varies and is hard to cache reliably.

**Solution:** Use `-clonedSourcePackagesDirPath .spm` to store packages in a deterministic location:

```bash
xcodebuild -resolvePackageDependencies \
  -clonedSourcePackagesDirPath .spm \
  -derivedDataPath DerivedData
```

This ensures:
- Consistent cache path across runs
- Faster cache key matching
- Separate from DerivedData for granular caching

### 4. Xcode Version Stability

**Problem:** Xcode 26.x with iOS 26.1 simulators is slow and flaky on GitHub Actions.

**Solution:** Prefer stable Xcode 16.x when available:

```yaml
- name: Select Xcode (prefer stable 16.x)
  run: |
    XCODE_PATH=$(ls -d /Applications/Xcode_16*.app 2>/dev/null | sort -V | tail -1)
    if [ -z "$XCODE_PATH" ]; then
      XCODE_PATH=$(ls -d /Applications/Xcode*.app 2>/dev/null | sort -V | tail -1)
    fi
    sudo xcode-select -s "$XCODE_PATH"
```

### 5. Deterministic Simulator Selection

**Problem:** Hardcoded simulator names (e.g., "iPhone 15 Pro") may not exist on all runners. Invalid fallback like `name=iPhone` causes destination errors.

**Solution:** Dynamically pick the first available iPhone simulator:

```yaml
- name: Determine simulator (first available iPhone)
  id: simulator
  run: |
    NAME=$(xcrun simctl list devices available | sed -n 's/.*(iPhone[^()]*) (.*) (available).*/\1/p' | head -1)
    if [ -z "$NAME" ]; then
      echo "No available iPhone simulator found" >&2
      xcrun simctl list devices available
      exit 1
    fi
    echo "Using simulator: $NAME"
    echo "name=$NAME" >> $GITHUB_OUTPUT
```

### 6. Simulator Reset

**Problem:** Parallel testing causes "instruments lockdown" timeouts (120+ seconds) when simulators have stale state.

**Solution:** Reset all simulators before testing:

```yaml
- name: Reset simulators (avoid instruments lockdown timeouts)
  run: |
    xcrun simctl shutdown all || true
    xcrun simctl erase all || true
```

### 7. Parallel Testing Limits

**Problem:** Running 4 parallel test workers causes simulator clone timeouts and lockdown service conflicts.

**Solution:** Limit to 2 workers and 2 concurrent simulator destinations:

```bash
xcodebuild test-without-building \
  -parallel-testing-enabled YES \
  -parallel-testing-worker-count 2 \
  -maximum-concurrent-test-simulator-destinations 2
```

### 8. Build-Test Separation

**Problem:** Combined build+test makes caching less effective and failures harder to diagnose.

**Solution:** Separate `build-for-testing` and `test-without-building`:

```yaml
- name: Build for testing
  run: |
    xcodebuild build-for-testing \
      -project AmakaFlowCompanion.xcodeproj \
      -scheme AmakaFlowCompanion \
      -destination "platform=iOS Simulator,name=iPhone 15 Pro" \
      -derivedDataPath DerivedData \
      -clonedSourcePackagesDirPath .spm \
      -parallelizeTargets \
      -jobs $(sysctl -n hw.ncpu)

- name: Run tests
  run: |
    xcodebuild test-without-building \
      -project AmakaFlowCompanion.xcodeproj \
      -scheme AmakaFlowCompanion \
      -only-testing:AmakaFlowCompanionTests \
      ...
```

### 9. Coverage Only on Nightly

**Problem:** Code coverage adds significant overhead to test execution.

**Solution:** Only enable coverage on scheduled nightly runs:

```yaml
COVERAGE_FLAG="NO"
if [ "${{ github.event_name }}" = "schedule" ]; then
  COVERAGE_FLAG="YES"
fi

xcodebuild test-without-building \
  -enableCodeCoverage $COVERAGE_FLAG
```

## Cache Key Strategy

### SwiftPM Cache

```yaml
key: spm-${{ runner.os }}-${{ steps.xcode.outputs.version }}-${{ hashFiles('**/Package.resolved', '...project.pbxproj') }}
restore-keys: |
  spm-${{ runner.os }}-${{ steps.xcode.outputs.version }}-
```

- Invalidates on: Package.resolved changes, project file changes
- Includes Xcode version to avoid compatibility issues

### DerivedData Cache

```yaml
key: deriveddata-${{ runner.os }}-${{ steps.xcode.outputs.version }}-${{ hashFiles('...project.pbxproj', '**/*.swift') }}
restore-keys: |
  deriveddata-${{ runner.os }}-${{ steps.xcode.outputs.version }}-
```

- Invalidates on: Project file changes, Swift source changes
- More aggressive invalidation since compiled artifacts are Xcode-version-specific

## Expected Runtimes

| Scenario | Expected Time |
|----------|---------------|
| Cold cache (first run) | 25-35 minutes |
| Warm cache (no changes) | 10-15 minutes |
| Warm cache (source changes only) | 15-20 minutes |

## Troubleshooting

### "instruments lockdown" timeouts
- Ensure simulator reset step runs before tests
- Check `-maximum-concurrent-test-simulator-destinations` is set
- Reduce `-parallel-testing-worker-count` if still seeing issues

### Cache misses every run
- Verify cache restore happens BEFORE resolve/build steps
- Check cache key hashes are deterministic
- Ensure `.spm` and `DerivedData` paths are consistent

### Project compatibility errors
- Dynamic Xcode selection should handle version mismatches
- If project requires specific Xcode version, pin it explicitly

## Related Files

- [.github/workflows/ios-tests.yml](../../.github/workflows/ios-tests.yml) - Main workflow
- [QUICK_START_TESTING.md](../../QUICK_START_TESTING.md) - Local testing guide
