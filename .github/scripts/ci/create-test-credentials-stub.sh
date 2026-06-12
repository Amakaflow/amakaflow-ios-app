#!/usr/bin/env bash
set -euo pipefail

cat > AmakaFlowCompanion/AmakaFlowCompanionUITests/TestCredentials.swift <<'EOF'
import Foundation
enum TestCredentials {
    static let testAuthSecret = "ci-stub-not-for-testing"
    static let userId = "ci_stub_user"
    static let userEmail = "ci@stub.local"
    static let userName = "CI Stub"
    static let apiBaseURL = "http://localhost:8001"
}
EOF
