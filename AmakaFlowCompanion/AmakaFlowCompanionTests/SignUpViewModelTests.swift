//
//  SignUpViewModelTests.swift
//  AmakaFlowCompanionTests
//
//  AMA-2007: Sign-up auth CTA and SwiftUI demo state coverage.
//

import Foundation
import XCTest
@testable import AmakaFlowCompanion

@MainActor
final class SignUpViewModelTests: XCTestCase {

    func testAppleSignIn_networkError_mapsToCTAError() async {
        let auth = MockSignUpAuth()
        auth.appleResult = .failure(URLError(.notConnectedToInternet))
        let viewModel = SignUpViewModel(auth: auth, errorReporter: MockSignUpErrorReporter())

        await viewModel.signInWithApple()

        XCTAssertEqual(auth.appleCallCount, 1)
        XCTAssertEqual(viewModel.error, .network(code: .notConnectedToInternet, requestId: nil))
        XCTAssertEqual(viewModel.failedAction, .apple)
        XCTAssertNil(viewModel.inFlightAction)
    }

    func testAppleSignIn_httpError_mapsToCTAError() async {
        let auth = MockSignUpAuth()
        auth.appleResult = .failure(APIError.serverErrorWithBody(503, "temporarily unavailable"))
        let viewModel = SignUpViewModel(auth: auth, errorReporter: MockSignUpErrorReporter())

        await viewModel.signInWithApple()

        XCTAssertEqual(auth.appleCallCount, 1)
        XCTAssertEqual(viewModel.error, .http(status: 503, body: "temporarily unavailable", requestId: nil))
        XCTAssertEqual(viewModel.failedAction, .apple)
        XCTAssertTrue(viewModel.error?.isRetryable == true)
    }

    func testAppleSignIn_unauthorized_mapsToUnauthenticatedCTAError() async {
        let auth = MockSignUpAuth()
        auth.appleResult = .failure(APIError.unauthorized)
        let viewModel = SignUpViewModel(auth: auth, errorReporter: MockSignUpErrorReporter())

        await viewModel.signInWithApple()

        XCTAssertEqual(auth.appleCallCount, 1)
        XCTAssertEqual(viewModel.error, .unauthenticated(requestId: nil))
        XCTAssertEqual(viewModel.failedAction, .apple)
        XCTAssertFalse(viewModel.error?.isRetryable == true)
    }

    func testContinueWithEmail_successPreflightsAuthAndPresentsClerkEmailFlow() async {
        let auth = MockSignUpAuth()
        let viewModel = SignUpViewModel(auth: auth, errorReporter: MockSignUpErrorReporter())

        await viewModel.continueWithEmail()

        XCTAssertEqual(auth.emailCallCount, 1)
        XCTAssertTrue(viewModel.isEmailAuthPresented)
        XCTAssertNil(viewModel.error)
    }

    func testContinueWithEmail_errorMapsThroughCTAErrorStack() async {
        let auth = MockSignUpAuth()
        auth.emailResult = .failure(URLError(.timedOut))
        let viewModel = SignUpViewModel(auth: auth, errorReporter: MockSignUpErrorReporter())

        await viewModel.continueWithEmail()

        XCTAssertEqual(auth.emailCallCount, 1)
        XCTAssertFalse(viewModel.isEmailAuthPresented)
        XCTAssertEqual(viewModel.error, .network(code: .timedOut, requestId: nil))
        XCTAssertEqual(viewModel.failedAction, .email)
    }

    func testReportCurrentError_sendsUserReportWithActionAndUserId() async {
        let auth = MockSignUpAuth()
        auth.emailResult = .failure(APIError.serverError(500))
        let reporter = MockSignUpErrorReporter()
        let viewModel = SignUpViewModel(
            auth: auth,
            errorReporter: reporter,
            userIdProvider: { "user-signup" }
        )

        await viewModel.continueWithEmail()
        viewModel.reportCurrentError()

        XCTAssertEqual(reporter.reports.count, 1)
        XCTAssertEqual(reporter.reports.first?.action, "auth_sign_in_email")
        XCTAssertEqual(reporter.reports.first?.error, .http(status: 500, body: nil, requestId: nil))
        XCTAssertNil(reporter.reports.first?.endpoint)
        XCTAssertEqual(reporter.reports.first?.userId, "user-signup")
    }

    func testReducedMotion_selectsStaticFirstFramePlayback() {
        XCTAssertEqual(SignUpDemoPlayback.mode(reduceMotion: true).mode, .staticFirstFrame)
        XCTAssertEqual(SignUpDemoPlayback.mode(reduceMotion: false).mode, .animatedLoop)
    }

    func testDemoTimeline_advancesThroughMockNarrativeAndLoops() {
        XCTAssertEqual(SignUpDemoTimeline.presentation(at: 0.1).phase, .suggest)
        XCTAssertEqual(SignUpDemoTimeline.presentation(at: 2.8).phase, .accept)
        XCTAssertEqual(SignUpDemoTimeline.presentation(at: 5.2).phase, .telegram)
        XCTAssertEqual(SignUpDemoTimeline.presentation(at: 8.2).phase, .reset)
        XCTAssertEqual(SignUpDemoTimeline.presentation(at: SignUpDemoTimeline.loopDuration + 0.1).phase, .suggest)
    }

    func testDemoPresentation_movesWorkoutCardTowardTelegramBubble() {
        let beforeDelivery = SignUpDemoTimeline.presentation(at: 4.0)
        let start = SignUpDemoTimeline.presentation(at: 4.7)
        let later = SignUpDemoTimeline.presentation(at: 6.4)

        XCTAssertEqual(beforeDelivery.phase, .accept)
        XCTAssertEqual(start.phase, .telegram)
        XCTAssertEqual(later.phase, .telegram)
        XCTAssertGreaterThan(later.workoutCardOffsetX, start.workoutCardOffsetX)
        XCTAssertGreaterThan(later.workoutCardOffsetY, start.workoutCardOffsetY)
        XCTAssertGreaterThan(later.telegramOpacity, beforeDelivery.telegramOpacity)
    }
}

@MainActor
private final class MockSignUpAuth: SignUpAuthenticating {
    var appleResult: Result<Void, Error> = .success(())
    var emailResult: Result<Void, Error> = .success(())
    private(set) var appleCallCount = 0
    private(set) var emailCallCount = 0

    func signInWithApple() async throws {
        appleCallCount += 1
        try appleResult.get()
    }

    func prepareEmailAuthentication() async throws {
        emailCallCount += 1
        try emailResult.get()
    }
}

private final class MockSignUpErrorReporter: ErrorReporting {
    struct Report: Equatable {
        let action: String
        let error: CTAError
        let endpoint: String?
        let userId: String?
    }

    private(set) var reports: [Report] = []

    func report(action: String, error: CTAError, endpoint: String?, userId: String?) {
        reports.append(Report(action: action, error: error, endpoint: endpoint, userId: userId))
    }
}
