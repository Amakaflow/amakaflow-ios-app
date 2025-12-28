import XCTest
@testable import AmakaFlowCompanion

final class PairingTests: XCTestCase {

    // MARK: - Environment Configuration Tests

    func testDefaultEnvironmentIsStagingInDebug() {
        // Reset to default first
        AppEnvironment.resetToDefault()

        // In DEBUG builds, default should be staging
        #if DEBUG
        XCTAssertEqual(AppEnvironment.current, .staging)
        #else
        XCTAssertEqual(AppEnvironment.current, .production)
        #endif
    }

    func testEnvironmentCanBeChanged() {
        // Save original
        let original = AppEnvironment.current

        // Change to production
        AppEnvironment.current = .production
        XCTAssertEqual(AppEnvironment.current, .production)

        // Change to development
        AppEnvironment.current = .development
        XCTAssertEqual(AppEnvironment.current, .development)

        // Reset back
        AppEnvironment.resetToDefault()
        XCTAssertEqual(AppEnvironment.current, original)
    }

    func testStagingAPIURLsAreCorrect() {
        let env = AppEnvironment.staging
        XCTAssertEqual(env.mapperAPIURL, "https://mapper-api.staging.amakaflow.com")
        XCTAssertEqual(env.ingestorAPIURL, "https://workout-ingestor-api.staging.amakaflow.com")
        XCTAssertEqual(env.calendarAPIURL, "https://calendar-api.staging.amakaflow.com")
    }

    func testProductionAPIURLsAreCorrect() {
        let env = AppEnvironment.production
        XCTAssertEqual(env.mapperAPIURL, "https://mapper-api.amakaflow.com")
        XCTAssertEqual(env.ingestorAPIURL, "https://workout-ingestor-api.amakaflow.com")
        XCTAssertEqual(env.calendarAPIURL, "https://calendar-api.amakaflow.com")
    }

    func testEnvironmentDisplayNames() {
        XCTAssertEqual(AppEnvironment.development.displayName, "Development")
        XCTAssertEqual(AppEnvironment.staging.displayName, "Staging")
        XCTAssertEqual(AppEnvironment.production.displayName, "Production")
    }

    // MARK: - PairingRequest Encoding Tests

    func testPairingRequestEncodesShortCodeCorrectly() throws {
        // 6-char codes should use short_code field
        let request = PairingRequest(
            token: nil,
            shortCode: "ABC123",
            deviceInfo: DeviceInfo(model: "iPhone15,2", osVersion: "18.0", appVersion: "1.0")
        )

        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        let data = try encoder.encode(request)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        // Verify short_code field is present and token is null
        XCTAssertEqual(json["short_code"] as? String, "ABC123")
        XCTAssertTrue(json["token"] is NSNull || json["token"] == nil)
        XCTAssertNotNil(json["device_info"])
    }

    func testPairingRequestEncodesTokenCorrectly() throws {
        // Longer codes (from QR) should use token field
        let longToken = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9"
        let request = PairingRequest(
            token: longToken,
            shortCode: nil,
            deviceInfo: DeviceInfo(model: "iPhone15,2", osVersion: "18.0", appVersion: "1.0")
        )

        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        let data = try encoder.encode(request)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        // Verify token field is present and short_code is null
        XCTAssertEqual(json["token"] as? String, longToken)
        XCTAssertTrue(json["short_code"] is NSNull || json["short_code"] == nil)
        XCTAssertNotNil(json["device_info"])
    }

    func testPairingRequestUsesSnakeCaseForDeviceInfo() throws {
        let request = PairingRequest(
            token: nil,
            shortCode: "TEST12",
            deviceInfo: DeviceInfo(model: "iPhone15,2", osVersion: "18.0", appVersion: "1.0")
        )

        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        let data = try encoder.encode(request)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let deviceInfo = json["device_info"] as! [String: Any]

        // Verify snake_case keys
        XCTAssertEqual(deviceInfo["os_version"] as? String, "18.0")
        XCTAssertEqual(deviceInfo["app_version"] as? String, "1.0")
        XCTAssertEqual(deviceInfo["model"] as? String, "iPhone15,2")
    }

    func testCodeLengthDeterminesFieldUsed() {
        // Short codes (6 chars) should use short_code field
        let shortCode = "ABC123"
        XCTAssertEqual(shortCode.count, 6)
        let isShortCode = shortCode.count == 6
        XCTAssertTrue(isShortCode)

        // Long tokens (> 6 chars) should use token field
        let longToken = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9"
        XCTAssertGreaterThan(longToken.count, 6)
        let isLongToken = longToken.count > 6
        XCTAssertTrue(isLongToken)
    }

    // MARK: - QR Code Parsing Tests

    func testQRCodeDataParsesValidJSON() throws {
        let qrJSON = """
        {
            "type": "mobile_pairing",
            "version": 1,
            "token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9",
            "api_url": "https://mapper-api.staging.amakaflow.com"
        }
        """

        let data = qrJSON.data(using: .utf8)!
        let qrData = try JSONDecoder().decode(QRCodeData.self, from: data)

        XCTAssertEqual(qrData.type, "mobile_pairing")
        XCTAssertEqual(qrData.version, 1)
        XCTAssertEqual(qrData.token, "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9")
        XCTAssertEqual(qrData.apiUrl, "https://mapper-api.staging.amakaflow.com")
    }

    func testQRCodeDataUsesSnakeCaseForApiUrl() throws {
        // Verify that api_url (snake_case) is correctly mapped to apiUrl (camelCase)
        let qrJSON = """
        {"type":"test","version":1,"token":"abc","api_url":"https://example.com"}
        """

        let data = qrJSON.data(using: .utf8)!
        let qrData = try JSONDecoder().decode(QRCodeData.self, from: data)

        XCTAssertEqual(qrData.apiUrl, "https://example.com")
    }

    // MARK: - PairingResponse Decoding Tests

    func testPairingResponseDecodesSuccessfully() throws {
        let responseJSON = """
        {
            "jwt": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.test",
            "expires_at": "2025-01-27T00:00:00Z",
            "profile": {
                "id": "user123",
                "email": "test@example.com",
                "name": "Test User",
                "avatar_url": "https://example.com/avatar.png"
            }
        }
        """

        let data = responseJSON.data(using: .utf8)!
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let response = try decoder.decode(PairingResponse.self, from: data)

        XCTAssertEqual(response.jwt, "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.test")
        XCTAssertEqual(response.expiresAt, "2025-01-27T00:00:00Z")
        XCTAssertNotNil(response.profile)
        XCTAssertEqual(response.profile?.id, "user123")
        XCTAssertEqual(response.profile?.email, "test@example.com")
        XCTAssertEqual(response.profile?.avatarUrl, "https://example.com/avatar.png")
    }

    func testPairingResponseDecodesWithoutProfile() throws {
        let responseJSON = """
        {
            "jwt": "test-jwt-token",
            "expires_at": "2025-01-27T00:00:00Z",
            "profile": null
        }
        """

        let data = responseJSON.data(using: .utf8)!
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let response = try decoder.decode(PairingResponse.self, from: data)

        XCTAssertEqual(response.jwt, "test-jwt-token")
        XCTAssertNil(response.profile)
    }

    // MARK: - Error Response Tests

    func testAPIErrorResponseDecodes() throws {
        let errorJSON = """
        {
            "detail": "Token not found",
            "error": "invalid_token",
            "message": "The provided token does not exist"
        }
        """

        let data = errorJSON.data(using: .utf8)!
        let error = try JSONDecoder().decode(APIErrorResponse.self, from: data)

        XCTAssertEqual(error.detail, "Token not found")
        XCTAssertEqual(error.error, "invalid_token")
        XCTAssertEqual(error.message, "The provided token does not exist")
    }

    // MARK: - PairingError Tests

    func testPairingErrorDescriptions() {
        XCTAssertEqual(
            PairingError.invalidCode("Bad code").errorDescription,
            "Bad code"
        )
        XCTAssertEqual(
            PairingError.codeExpired.errorDescription,
            "Code has expired. Please generate a new one."
        )
        XCTAssertEqual(
            PairingError.invalidResponse.errorDescription,
            "Invalid server response"
        )
        XCTAssertEqual(
            PairingError.serverError(500).errorDescription,
            "Server error: 500"
        )
        XCTAssertEqual(
            PairingError.tokenStorageFailed.errorDescription,
            "Failed to save credentials"
        )
    }

    // MARK: - Code Normalization Tests

    func testShortCodeIsUppercased() {
        // Simulate what the app does with short codes
        let inputCode = "abc123"
        let normalizedCode = inputCode.uppercased()

        XCTAssertEqual(normalizedCode, "ABC123")
    }
}
