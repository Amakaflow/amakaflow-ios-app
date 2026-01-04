# Testing with E2E Test User

This guide explains how to run the iOS app with the E2E test user for manual testing against the local development backend.

## Prerequisites

1. **Local backend running** - The mapper-api must be running on `localhost:8001`
   ```bash
   # In the mapper-api directory
   make dev
   # or
   docker-compose up
   ```

2. **iOS Simulator** - Have an iOS simulator available (e.g., iPhone 17 Pro)

3. **App built** - Build the app for the simulator:
   ```bash
   cd AmakaFlowCompanion
   xcodebuild -scheme AmakaFlowCompanion \
     -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
     -configuration Debug build
   ```

## Test User Credentials

| Field | Value |
|-------|-------|
| User ID | `user_37lZCcU9AJ9b7MX2H71dZ2CuX2u` |
| Email | `soopergeri+e2etest@gmail.com` |
| Auth Secret | `e2e-test-secret-dev-only` |

## Quick Start

### 1. Boot the Simulator

```bash
xcrun simctl boot "iPhone 17 Pro" 2>/dev/null || true
open -a Simulator
```

### 2. Install the App

```bash
# Find the built app (adjust path based on your Xcode DerivedData location)
xcrun simctl install "iPhone 17 Pro" \
  ~/Library/Developer/Xcode/DerivedData/AmakaFlowCompanion-*/Build/Products/Debug-iphonesimulator/AmakaFlowCompanion.app
```

### 3. Launch with Test User

```bash
SIMCTL_CHILD_TEST_AUTH_SECRET="e2e-test-secret-dev-only" \
SIMCTL_CHILD_TEST_USER_ID="user_37lZCcU9AJ9b7MX2H71dZ2CuX2u" \
SIMCTL_CHILD_TEST_USER_EMAIL="soopergeri+e2etest@gmail.com" \
SIMCTL_CHILD_TEST_API_BASE_URL="http://localhost:8001" \
SIMCTL_CHILD_TEST_ENVIRONMENT="development" \
xcrun simctl launch "iPhone 17 Pro" com.myamaka.AmakaFlowCompanion
```

## One-Liner (Copy & Paste)

Build, install, and launch in one command:

```bash
cd /path/to/amakaflow-ios-app/AmakaFlowCompanion && \
xcodebuild -scheme AmakaFlowCompanion -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet build && \
xcrun simctl install "iPhone 17 Pro" ~/Library/Developer/Xcode/DerivedData/AmakaFlowCompanion-*/Build/Products/Debug-iphonesimulator/AmakaFlowCompanion.app && \
SIMCTL_CHILD_TEST_AUTH_SECRET="e2e-test-secret-dev-only" \
SIMCTL_CHILD_TEST_USER_ID="user_37lZCcU9AJ9b7MX2H71dZ2CuX2u" \
SIMCTL_CHILD_TEST_USER_EMAIL="soopergeri+e2etest@gmail.com" \
SIMCTL_CHILD_TEST_API_BASE_URL="http://localhost:8001" \
SIMCTL_CHILD_TEST_ENVIRONMENT="development" \
xcrun simctl launch "iPhone 17 Pro" com.myamaka.AmakaFlowCompanion
```

## Verify Backend Has Test Data

Check that the local backend has workout history for the test user:

```bash
curl -s \
  -H "X-Test-Auth: e2e-test-secret-dev-only" \
  -H "X-Test-User-Id: user_37lZCcU9AJ9b7MX2H71dZ2CuX2u" \
  "http://localhost:8001/workouts/completions?limit=5" | jq
```

## Environment Variables Explained

| Variable | Purpose |
|----------|---------|
| `SIMCTL_CHILD_TEST_AUTH_SECRET` | Bypasses JWT auth using X-Test-Auth header |
| `SIMCTL_CHILD_TEST_USER_ID` | Sets the authenticated user ID |
| `SIMCTL_CHILD_TEST_USER_EMAIL` | Sets the user's email for profile display |
| `SIMCTL_CHILD_TEST_API_BASE_URL` | Overrides the API base URL (default is based on environment) |
| `SIMCTL_CHILD_TEST_ENVIRONMENT` | Sets app environment: development, staging, or production |

Note: The `SIMCTL_CHILD_` prefix is stripped by `simctl` before passing to the app.

## Troubleshooting

### App shows empty workout history
- Verify local backend is running: `curl http://localhost:8001/health`
- Check test user has data: use the curl command above
- Make sure all environment variables are set correctly

### App not picking up environment variables
- Terminate the app first: `xcrun simctl terminate "iPhone 17 Pro" com.myamaka.AmakaFlowCompanion`
- Re-launch with the environment variables

### Cannot resolve localhost from simulator
- iOS Simulator should resolve localhost to your Mac
- If issues persist, try using your Mac's IP address instead

## Related Docs

- [QUICK_START_TESTING.md](./QUICK_START_TESTING.md) - General testing guide
- [TESTING_WORKOUT_SYNC.md](./TESTING_WORKOUT_SYNC.md) - WorkoutKit sync testing
- [TESTING_FOLLOW_ALONG.md](./TESTING_FOLLOW_ALONG.md) - Follow-along workout testing
