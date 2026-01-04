#!/bin/bash
#
# setup-paired-simulators.sh
# AmakaFlow iOS App
#
# Sets up paired iPhone + Apple Watch simulators for E2E testing (AMA-232)
#
# Usage:
#   ./scripts/setup-paired-simulators.sh [--create] [--boot] [--list]
#
# Options:
#   --create    Create new paired simulators if they don't exist
#   --boot      Boot the paired simulators
#   --list      List available paired simulators
#   --help      Show this help message
#

set -e

# Configuration
IPHONE_MODEL="iPhone 16 Pro"
WATCH_MODEL="Apple Watch Series 10 (46mm)"
IPHONE_RUNTIME="iOS 18.4"
WATCH_RUNTIME="watchOS 11.4"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Show help
show_help() {
    echo "AmakaFlow Paired Simulator Setup"
    echo ""
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --create    Create new paired simulators"
    echo "  --boot      Boot the paired simulators"
    echo "  --list      List available simulators and pairings"
    echo "  --status    Show current simulator status"
    echo "  --help      Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 --list                    # List all simulators"
    echo "  $0 --create --boot           # Create and boot paired simulators"
    echo "  $0 --status                  # Show current status"
}

# List all available simulators
list_simulators() {
    log_info "Available iPhone Simulators:"
    xcrun simctl list devices available | grep -E "iPhone|iPad" | head -10

    echo ""
    log_info "Available Watch Simulators:"
    xcrun simctl list devices available | grep -E "Apple Watch" | head -10

    echo ""
    log_info "Current Pairings:"
    xcrun simctl list pairs
}

# Get UDID of a simulator by name
get_simulator_udid() {
    local name="$1"
    xcrun simctl list devices available -j | \
        python3 -c "
import json, sys
data = json.load(sys.stdin)
for runtime, devices in data.get('devices', {}).items():
    for device in devices:
        if device['name'] == '$name' and device['isAvailable']:
            print(device['udid'])
            sys.exit(0)
" 2>/dev/null || echo ""
}

# Check if simulators are paired
check_pairing() {
    local iphone_udid="$1"
    local watch_udid="$2"

    xcrun simctl list pairs -j | \
        python3 -c "
import json, sys
data = json.load(sys.stdin)
for pair_id, pair in data.get('pairs', {}).items():
    if pair.get('watch', {}).get('udid') == '$watch_udid' and \
       pair.get('phone', {}).get('udid') == '$iphone_udid':
        print('paired')
        sys.exit(0)
print('not_paired')
" 2>/dev/null || echo "error"
}

# Create paired simulators
create_paired_simulators() {
    log_info "Looking for existing simulators..."

    # Find iPhone simulator
    local iphone_udid=$(get_simulator_udid "$IPHONE_MODEL")
    if [ -z "$iphone_udid" ]; then
        log_info "Creating $IPHONE_MODEL simulator..."
        # Get runtime identifier
        local ios_runtime=$(xcrun simctl list runtimes -j | \
            python3 -c "
import json, sys
data = json.load(sys.stdin)
for runtime in data.get('runtimes', []):
    if 'iOS' in runtime.get('name', '') and runtime.get('isAvailable', False):
        print(runtime['identifier'])
        break
")
        if [ -n "$ios_runtime" ]; then
            iphone_udid=$(xcrun simctl create "$IPHONE_MODEL" "com.apple.CoreSimulator.SimDeviceType.iPhone-16-Pro" "$ios_runtime")
            log_info "Created iPhone simulator: $iphone_udid"
        else
            log_error "No available iOS runtime found"
            return 1
        fi
    else
        log_info "Found existing $IPHONE_MODEL: $iphone_udid"
    fi

    # Find Watch simulator
    local watch_udid=$(get_simulator_udid "$WATCH_MODEL")
    if [ -z "$watch_udid" ]; then
        log_info "Creating $WATCH_MODEL simulator..."
        local watch_runtime=$(xcrun simctl list runtimes -j | \
            python3 -c "
import json, sys
data = json.load(sys.stdin)
for runtime in data.get('runtimes', []):
    if 'watchOS' in runtime.get('name', '') and runtime.get('isAvailable', False):
        print(runtime['identifier'])
        break
")
        if [ -n "$watch_runtime" ]; then
            watch_udid=$(xcrun simctl create "$WATCH_MODEL" "com.apple.CoreSimulator.SimDeviceType.Apple-Watch-Series-10-46mm" "$watch_runtime")
            log_info "Created Watch simulator: $watch_udid"
        else
            log_error "No available watchOS runtime found"
            return 1
        fi
    else
        log_info "Found existing $WATCH_MODEL: $watch_udid"
    fi

    # Check if already paired
    local pairing_status=$(check_pairing "$iphone_udid" "$watch_udid")
    if [ "$pairing_status" = "paired" ]; then
        log_info "Simulators are already paired"
    else
        log_info "Pairing simulators..."
        xcrun simctl pair "$watch_udid" "$iphone_udid"
        log_info "Successfully paired $IPHONE_MODEL with $WATCH_MODEL"
    fi

    echo ""
    echo "iPhone UDID: $iphone_udid"
    echo "Watch UDID: $watch_udid"
}

# Boot paired simulators
boot_simulators() {
    local iphone_udid=$(get_simulator_udid "$IPHONE_MODEL")
    local watch_udid=$(get_simulator_udid "$WATCH_MODEL")

    if [ -z "$iphone_udid" ]; then
        log_error "iPhone simulator not found. Run with --create first."
        return 1
    fi

    log_info "Booting $IPHONE_MODEL..."
    xcrun simctl boot "$iphone_udid" 2>/dev/null || log_warn "iPhone may already be booted"

    if [ -n "$watch_udid" ]; then
        log_info "Booting $WATCH_MODEL..."
        xcrun simctl boot "$watch_udid" 2>/dev/null || log_warn "Watch may already be booted"
    fi

    log_info "Opening Simulator app..."
    open -a Simulator

    log_info "Simulators booted successfully"
}

# Show current status
show_status() {
    log_info "Current Simulator Status:"
    echo ""

    local iphone_udid=$(get_simulator_udid "$IPHONE_MODEL")
    local watch_udid=$(get_simulator_udid "$WATCH_MODEL")

    if [ -n "$iphone_udid" ]; then
        echo "iPhone: $IPHONE_MODEL ($iphone_udid)"
        xcrun simctl list devices | grep "$iphone_udid" || true
    else
        echo "iPhone: Not created"
    fi

    echo ""

    if [ -n "$watch_udid" ]; then
        echo "Watch: $WATCH_MODEL ($watch_udid)"
        xcrun simctl list devices | grep "$watch_udid" || true
    else
        echo "Watch: Not created"
    fi

    echo ""
    log_info "Pairing Status:"
    if [ -n "$iphone_udid" ] && [ -n "$watch_udid" ]; then
        local pairing=$(check_pairing "$iphone_udid" "$watch_udid")
        echo "Paired: $pairing"
    else
        echo "Cannot check pairing - simulators not created"
    fi
}

# Run E2E tests
run_tests() {
    log_info "Running E2E UI Tests..."

    local iphone_udid=$(get_simulator_udid "$IPHONE_MODEL")
    if [ -z "$iphone_udid" ]; then
        log_error "iPhone simulator not found"
        return 1
    fi

    cd "$(dirname "$0")/../AmakaFlowCompanion"

    xcodebuild test \
        -project AmakaFlowCompanion.xcodeproj \
        -scheme AmakaFlowCompanion \
        -destination "platform=iOS Simulator,id=$iphone_udid" \
        -only-testing:AmakaFlowCompanionUITests \
        -parallel-testing-enabled NO \
        2>&1 | xcpretty || true
}

# Main
main() {
    if [ $# -eq 0 ]; then
        show_help
        exit 0
    fi

    local do_create=false
    local do_boot=false
    local do_list=false
    local do_status=false
    local do_test=false

    while [ $# -gt 0 ]; do
        case "$1" in
            --create)
                do_create=true
                ;;
            --boot)
                do_boot=true
                ;;
            --list)
                do_list=true
                ;;
            --status)
                do_status=true
                ;;
            --test)
                do_test=true
                ;;
            --help|-h)
                show_help
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
        shift
    done

    [ "$do_list" = true ] && list_simulators
    [ "$do_create" = true ] && create_paired_simulators
    [ "$do_boot" = true ] && boot_simulators
    [ "$do_status" = true ] && show_status
    [ "$do_test" = true ] && run_tests
}

main "$@"
