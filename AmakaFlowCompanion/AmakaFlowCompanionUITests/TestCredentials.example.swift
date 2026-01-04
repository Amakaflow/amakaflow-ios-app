//
//  TestCredentials.example.swift
//  AmakaFlowCompanionUITests
//
//  TEMPLATE FILE - Copy to TestCredentials.swift and add your credentials
//  TestCredentials.swift should be in .gitignore
//
//  To generate a test JWT, run:
//  cd mapper-api && python3 -c "
//  import jwt
//  from datetime import datetime, timedelta, timezone
//  JWT_SECRET = 'your-jwt-secret-here'
//  now = datetime.now(timezone.utc)
//  expiry = now + timedelta(days=365)
//  payload = {
//      'sub': 'e2e_test_user',
//      'iat': int(now.timestamp()),
//      'exp': int(expiry.timestamp()),
//      'iss': 'amakaflow',
//      'aud': 'ios_companion',
//      'email': 'your-test-email@example.com',
//      'name': 'E2E Test User'
//  }
//  print(jwt.encode(payload, JWT_SECRET, algorithm='HS256'))
//  "
//

import Foundation

/// Test credentials for E2E UI testing
/// These credentials bypass the normal pairing flow
///
/// IMPORTANT: Copy this file to TestCredentials.swift and fill in your values
/// This example file uses a different enum name to avoid conflicts
enum TestCredentialsExample {
    /// Long-lived JWT for test account
    /// Replace with your generated JWT
    static let pairingToken = "YOUR_JWT_TOKEN_HERE"

    /// Test user ID matching the JWT 'sub' claim
    static let userId = "e2e_test_user"

    /// Test user email
    static let userEmail = "your-test-email@example.com"

    /// Test user display name
    static let userName = "E2E Test User"

    /// API base URL for testing (use development/localhost)
    static let apiBaseURL = "http://localhost:8001"
}
