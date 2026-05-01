//
//  ShareExtensionTests.swift
//  AmakaFlowCompanionTests
//
//  AMA-1642: regression tests for the Share Extension state-binding fix.
//
//  The original bug: ShareViewController drove the SwiftUI view's @State via
//  `hostingController?.rootView.state = .importing`, which is a no-op because
//  UIHostingController.rootView returns the view as a value type. The fix
//  introduced ShareImportViewModel: ObservableObject so a UIKit container can
//  drive @Published state and have SwiftUI actually re-render.
//
//  These tests reference the production `ShareImportViewModel` and
//  `ShareImportState` directly. The types live in
//  `AmakaFlowShare/ShareImportViewModel.swift` and are dual-membered into
//  this test target's Compile Sources phase, so a type-shape regression
//  (e.g. dropping @Published) will break the build, not just sail past
//  inline copies.
//

import Combine
import XCTest

@MainActor
final class ShareExtensionTests: XCTestCase {

    // MARK: - State binding (AMA-1642 root-cause regression guard)

    /// Mutating the view model's `state` must publish the change so a
    /// SwiftUI consumer (`ShareExtensionView`) re-renders. This is the
    /// regression guard for the AMA-1642 root cause: the previous
    /// `@State` storage on `ShareExtensionView` couldn't be driven from
    /// outside via `hostingController?.rootView.state = ...`, so
    /// `.importing` / `.success` / `.error` transitions were invisible.
    /// With `@Published` on an `ObservableObject`, mutations propagate.
    func test_shareImportViewModel_publishesStateTransitions() {
        let viewModel = ShareImportViewModel()

        var receivedStates: [ShareImportState] = []
        var cancellables = Set<AnyCancellable>()
        let exp = expectation(description: "publisher emits 4 values (initial + 3 mutations)")
        exp.expectedFulfillmentCount = 4

        viewModel.$state.sink { state in
            receivedStates.append(state)
            exp.fulfill()
        }
        .store(in: &cancellables)

        viewModel.state = .importing
        viewModel.state = .success("Imported")
        viewModel.state = .error("Boom")

        wait(for: [exp], timeout: 0.5)
        XCTAssertEqual(receivedStates, [
            .ready,
            .importing,
            .success("Imported"),
            .error("Boom"),
        ])
    }

    func test_shareImportViewModel_initialStateIsReady() {
        let viewModel = ShareImportViewModel()
        XCTAssertEqual(viewModel.state, .ready)
    }

    /// Verifies that mutating `state` triggers the `objectWillChange`
    /// publisher SwiftUI uses to re-render. If someone accidentally
    /// removes `@Published` (the AMA-1642 regression vector), this test
    /// will start failing because objectWillChange wouldn't fire.
    func test_shareImportViewModel_objectWillChangeFiresOnMutation() {
        let viewModel = ShareImportViewModel()
        var willChangeCount = 0
        var cancellables = Set<AnyCancellable>()

        viewModel.objectWillChange.sink { _ in
            willChangeCount += 1
        }
        .store(in: &cancellables)

        viewModel.state = .importing
        viewModel.state = .error("x")

        XCTAssertEqual(willChangeCount, 2, "objectWillChange should fire once per @Published mutation")
    }

    // MARK: - State equality (round-trip on the enum used by callers)

    /// Production tests the custom Equatable impl that
    /// `ShareViewController` and `ShareExtensionView` rely on for state
    /// transitions and view re-render gating.
    func test_shareImportState_equalityCovers_associatedValues() {
        XCTAssertEqual(ShareImportState.success("a"), .success("a"))
        XCTAssertNotEqual(ShareImportState.success("a"), .success("b"))
        XCTAssertEqual(ShareImportState.error("x"), .error("x"))
        XCTAssertNotEqual(ShareImportState.error("x"), .error("y"))
        XCTAssertNotEqual(ShareImportState.ready, .importing)
        XCTAssertNotEqual(ShareImportState.success("a"), .error("a"))
        XCTAssertEqual(ShareImportState.loading, .loading)
        XCTAssertEqual(ShareImportState.ready, .ready)
        XCTAssertEqual(ShareImportState.importing, .importing)
    }
}
