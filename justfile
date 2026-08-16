# AmakaFlow iOS justfile
# Local development recipes for macOS. Linux agents cannot run these.

# Default destination: pick the first available iPhone simulator
_default_sim := `xcrun simctl list devices available | awk '!found && match($0, /iPhone [^(]*/) {name = substr($0, RSTART, RLENGTH); sub(/[[:space:]]+$/, "", name); print name; found = 1}'`

# Project configuration
project := "AmakaFlowCompanion/AmakaFlowCompanion.xcodeproj"
scheme := "AmakaFlowCompanion"
derived_data := "AmakaFlowCompanion/DerivedData"
spm_dir := "AmakaFlowCompanion/.spm"

# Clerk keys for build (same as CI)
clerk_dev := "pk_test_c29saWQtY2hpY2tlbi01MC5jbGVyay5hY2NvdW50cy5kZXYk"
clerk_staging := "pk_test_cnVsaW5nLW1pdGUtODQuY2xlcmsuYWNjb3VudHMuZGV2JA"

# Build Debug-sim .app with persistent DerivedData
ios-build:
    #!/usr/bin/env bash
    set -euo pipefail
    
    # Create stub TestCredentials if missing
    if [ ! -f AmakaFlowCompanion/AmakaFlowCompanionUITests/TestCredentials.swift ]; then
        .github/scripts/ci/create-test-credentials-stub.sh
    fi
    
    # Pick simulator using the same logic as CI
    SIM_NAME="{{ _default_sim }}"
    echo "Building for simulator: $SIM_NAME"
    
    xcodebuild build-for-testing \
        -project {{ project }} \
        -scheme {{ scheme }} \
        -configuration Debug \
        -destination "platform=iOS Simulator,name=$SIM_NAME" \
        -derivedDataPath {{ derived_data }} \
        -clonedSourcePackagesDirPath {{ spm_dir }} \
        -parallelizeTargets \
        -jobs $(sysctl -n hw.ncpu) \
        CLERK_PUBLISHABLE_KEY_DEV="{{ clerk_dev }}" \
        CLERK_PUBLISHABLE_KEY_STAGING="{{ clerk_staging }}" \
        CLERK_PUBLISHABLE_KEY_PRODUCTION="{{ clerk_staging }}"

# Run EditorV2 tests only
ios-test-editorv2:
    #!/usr/bin/env bash
    set -euo pipefail
    
    SIM_NAME="{{ _default_sim }}"
    echo "Running EditorV2 tests on simulator: $SIM_NAME"
    
    # Boot the simulator
    xcrun simctl boot "$SIM_NAME" || true
    xcrun simctl bootstatus "$SIM_NAME" -b
    
    # Discover all EditorV2*Tests.swift files and build -only-testing args
    ONLY_FLAGS=()
    while IFS= read -r test_file; do
        if [ -f "$test_file" ]; then
            test_class=$(basename "$test_file" .swift)
            ONLY_FLAGS+=("-only-testing:AmakaFlowCompanionTests/${test_class}")
        fi
    done < <(find AmakaFlowCompanion/AmakaFlowCompanionTests -name "EditorV2*Tests.swift" -type f 2>/dev/null || true)
    
    if [ ${#ONLY_FLAGS[@]} -eq 0 ]; then
        echo "ERROR: No EditorV2*Tests.swift files found"
        exit 1
    fi
    
    echo "Running ${#ONLY_FLAGS[@]} EditorV2 test class(es)"
    
    # Remove old result bundle
    rm -rf {{ derived_data }}/Build/Products/Debug-iphonesimulator/TestResults
    
    xcodebuild test-without-building \
        -project {{ project }} \
        -scheme {{ scheme }} \
        -destination "platform=iOS Simulator,name=$SIM_NAME" \
        -derivedDataPath {{ derived_data }} \
        -clonedSourcePackagesDirPath {{ spm_dir }} \
        "${ONLY_FLAGS[@]}" \
        -resultBundlePath TestResults \
        -enableCodeCoverage NO \
        -parallel-testing-enabled YES \
        -parallel-testing-worker-count 2

# Run impacted tests based on git diff against origin/main
ios-test-impacted BASE="origin/main":
    #!/usr/bin/env bash
    set -euo pipefail
    
    # Run affected-tests script
    AFFECTED=$(.github/scripts/affected-tests-ios.sh {{ BASE }})
    
    echo "Affected tests: $AFFECTED"
    
    if [ "$AFFECTED" = "NONE" ]; then
        echo "No tests affected by changes."
        exit 0
    fi
    
    SIM_NAME="{{ _default_sim }}"
    echo "Running tests on simulator: $SIM_NAME"
    
    # Boot the simulator
    xcrun simctl boot "$SIM_NAME" || true
    xcrun simctl bootstatus "$SIM_NAME" -b
    
    # Remove old result bundle
    rm -rf {{ derived_data }}/Build/Products/Debug-iphonesimulator/TestResults
    
    if [ "$AFFECTED" = "FULL" ]; then
        echo "Running full test suite (FULL mode)"
        xcodebuild test-without-building \
            -project {{ project }} \
            -scheme {{ scheme }} \
            -destination "platform=iOS Simulator,name=$SIM_NAME" \
            -derivedDataPath {{ derived_data }} \
            -clonedSourcePackagesDirPath {{ spm_dir }} \
            -only-testing:AmakaFlowCompanionTests \
            -resultBundlePath TestResults \
            -enableCodeCoverage NO \
            -parallel-testing-enabled YES \
            -parallel-testing-worker-count 2
    else
        # Build xcodebuild args with -only-testing for each affected test
        ONLY_FLAGS=()
        for test in $AFFECTED; do
            ONLY_FLAGS+=("-only-testing:${test}")
        done
        
        xcodebuild test-without-building \
            -project {{ project }} \
            -scheme {{ scheme }} \
            -destination "platform=iOS Simulator,name=$SIM_NAME" \
            -derivedDataPath {{ derived_data }} \
            -clonedSourcePackagesDirPath {{ spm_dir }} \
            "${ONLY_FLAGS[@]}" \
            -resultBundlePath TestResults \
            -enableCodeCoverage NO \
            -parallel-testing-enabled YES \
            -parallel-testing-worker-count 2
    fi

# Run full unit test suite
ios-test-full:
    #!/usr/bin/env bash
    set -euo pipefail
    
    SIM_NAME="{{ _default_sim }}"
    echo "Running full test suite on simulator: $SIM_NAME"
    
    # Boot the simulator
    xcrun simctl boot "$SIM_NAME" || true
    xcrun simctl bootstatus "$SIM_NAME" -b
    
    # Remove old result bundle
    rm -rf {{ derived_data }}/Build/Products/Debug-iphonesimulator/TestResults
    
    xcodebuild test-without-building \
        -project {{ project }} \
        -scheme {{ scheme }} \
        -destination "platform=iOS Simulator,name=$SIM_NAME" \
        -derivedDataPath {{ derived_data }} \
        -clonedSourcePackagesDirPath {{ spm_dir }} \
        -only-testing:AmakaFlowCompanionTests \
        -resultBundlePath TestResults \
        -enableCodeCoverage NO \
        -parallel-testing-enabled YES \
        -parallel-testing-worker-count 2

# Run SwiftLint with strict mode and baseline (same as CI)
ios-lint:
    #!/usr/bin/env bash
    set -euo pipefail
    
    if ! command -v swiftlint &> /dev/null; then
        echo "ERROR: swiftlint is not installed"
        echo "Install with: brew install swiftlint"
        exit 1
    fi
    
    echo "Running SwiftLint (strict mode with baseline)..."
    swiftlint lint --strict --baseline .swiftlint-baseline.yml
