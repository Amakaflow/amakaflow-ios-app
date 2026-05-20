#!/usr/bin/env bash
#
# AMA-1854 — Crash-free startup gate (v1-gap-6, Production-Ready v1).
#
# Installs the freshly-built .app on a clean iOS Simulator, launches it,
# waits for the configured grace period, and asserts the process is
# still running AND no fresh crash report appeared in
# ~/Library/Logs/DiagnosticReports/. Catches the cold-launch class of
# bug BEFORE the App Store reviewer (or your real users) does.
#
# Wired into .github/workflows/ios-cold-launch-matrix.yml on every PR.
#
# Usage:
#   scripts/cold-launch-check.sh \
#     --sim-udid <UDID> \
#     --app-path /path/to/AmakaFlowCompanion.app \
#     [--bundle-id com.myamaka.AmakaFlowCompanion] \
#     [--grace-seconds 60] \
#     [--screenshot-path /tmp/cold-launch-evidence.png]
#
# Exit codes:
#   0 — process alive at +grace AND no crash report — GATE PASSES
#   1 — process died OR a crash report dropped — GATE FAILS
#   2 — usage / arg / sim error (test infrastructure problem; not a
#       product crash, but the gate cannot rule on this run)
#
# Designed to be run repeatedly on the SAME sim. Resets the sim
# between runs by uninstalling the app + clearing fresh crash reports.

set -euo pipefail

SIM_UDID=""
APP_PATH=""
BUNDLE_ID="com.myamaka.AmakaFlowCompanion"
GRACE_SECONDS=60
SCREENSHOT_PATH=""

usage() {
  sed -n '4,29p' "$0" | sed 's/^# \{0,1\}//'
  exit "${1:-2}"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --sim-udid)        SIM_UDID="$2"; shift 2 ;;
    --app-path)        APP_PATH="$2"; shift 2 ;;
    --bundle-id)       BUNDLE_ID="$2"; shift 2 ;;
    --grace-seconds)   GRACE_SECONDS="$2"; shift 2 ;;
    --screenshot-path) SCREENSHOT_PATH="$2"; shift 2 ;;
    -h|--help)         usage 0 ;;
    *)                 echo "Unknown arg: $1" >&2; usage 2 ;;
  esac
done

if [[ -z "$SIM_UDID" || -z "$APP_PATH" ]]; then
  echo "ERROR: --sim-udid and --app-path are required" >&2
  usage 2
fi

if [[ ! -d "$APP_PATH" ]]; then
  echo "ERROR: --app-path not a directory: $APP_PATH" >&2
  exit 2
fi

# Capture a baseline of fresh crash reports so we only flag NEW ones.
# DiagnosticReports lives under the user library; sim crashes get
# written there with a *.ips file tagged by the process name.
CRASH_DIR="$HOME/Library/Logs/DiagnosticReports"
mkdir -p "$CRASH_DIR"
BASELINE_FILE="$(mktemp -t cold-launch-baseline)"
ls -1 "$CRASH_DIR" 2>/dev/null | sort > "$BASELINE_FILE" || true

echo "[cold-launch] sim=$SIM_UDID app=$APP_PATH bundle=$BUNDLE_ID grace=${GRACE_SECONDS}s"

# 1. Boot the sim if not already booted.
state=$(xcrun simctl list devices 2>/dev/null | grep -E "\($SIM_UDID\)" | sed -E 's/.*\((Booted|Shutdown)\).*/\1/' | head -1)
if [[ "$state" != "Booted" ]]; then
  echo "[cold-launch] booting sim..."
  xcrun simctl boot "$SIM_UDID" || true
  # Wait for boot to settle
  for _ in {1..30}; do
    state=$(xcrun simctl list devices 2>/dev/null | grep -E "\($SIM_UDID\)" | sed -E 's/.*\((Booted|Shutdown)\).*/\1/' | head -1)
    [[ "$state" == "Booted" ]] && break
    sleep 1
  done
fi

# 2. Uninstall + reinstall the app for a clean state.
echo "[cold-launch] uninstall any prior instance..."
xcrun simctl uninstall "$SIM_UDID" "$BUNDLE_ID" 2>/dev/null || true

echo "[cold-launch] install $APP_PATH..."
xcrun simctl install "$SIM_UDID" "$APP_PATH"

# 3. Launch + capture PID.
echo "[cold-launch] launch $BUNDLE_ID..."
launch_output=$(xcrun simctl launch "$SIM_UDID" "$BUNDLE_ID" 2>&1)
echo "$launch_output"
# Output is like "com.myamaka.AmakaFlowCompanion: 12345" — parse the PID
PID=$(echo "$launch_output" | sed -E 's/.*:[[:space:]]*([0-9]+).*/\1/' | head -1)

if [[ -z "$PID" || ! "$PID" =~ ^[0-9]+$ ]]; then
  echo "ERROR: could not parse PID from launch output" >&2
  rm -f "$BASELINE_FILE"
  exit 2
fi
echo "[cold-launch] app PID=$PID — waiting ${GRACE_SECONDS}s..."

# 4. Wait grace period, polling at half-grace for an early screenshot.
half=$((GRACE_SECONDS / 2))
sleep "$half"
if [[ -n "$SCREENSHOT_PATH" ]]; then
  echo "[cold-launch] capturing evidence screenshot at +${half}s -> $SCREENSHOT_PATH"
  xcrun simctl io "$SIM_UDID" screenshot "$SCREENSHOT_PATH" 2>/dev/null || \
    echo "[cold-launch] WARN: screenshot capture failed (non-fatal)"
fi
sleep "$((GRACE_SECONDS - half))"

# 5. Assert process still alive.
# `simctl spawn ... launchctl print system/${PID}` would be most robust
# but `kill -0` works too — and runs in the host context.
if kill -0 "$PID" 2>/dev/null; then
  PROCESS_ALIVE=1   # alive (good)
else
  PROCESS_ALIVE=0   # dead (bad)
  echo "❌ FAIL: app process $PID is GONE after ${GRACE_SECONDS}s — cold-launch crash" >&2
  echo "::error::Cold-launch crash on sim $SIM_UDID: $BUNDLE_ID died within ${GRACE_SECONDS}s"
fi

# 6. Check for fresh crash reports.
CURRENT_FILE="$(mktemp -t cold-launch-current)"
ls -1 "$CRASH_DIR" 2>/dev/null | sort > "$CURRENT_FILE" || true
NEW_CRASHES=$(comm -13 "$BASELINE_FILE" "$CURRENT_FILE" | grep -i -E "AmakaFlow|$BUNDLE_ID" || true)
rm -f "$BASELINE_FILE" "$CURRENT_FILE"

NO_NEW_CRASH=1
if [[ -n "$NEW_CRASHES" ]]; then
  echo "❌ FAIL: new crash report(s) appeared:" >&2
  echo "$NEW_CRASHES" >&2
  echo "::error::Cold-launch crash report detected for $BUNDLE_ID"
  NO_NEW_CRASH=0
fi

# 7. Final verdict.
if [[ "$PROCESS_ALIVE" == "1" && "$NO_NEW_CRASH" == "1" ]]; then
  echo "✅ PASS: $BUNDLE_ID alive at +${GRACE_SECONDS}s, no crash reports"
  exit 0
fi
exit 1
