//
//  WorkoutCompletionViewModelTests.swift
//  AmakaFlowCompanionTests
//
//  Unit tests for WorkoutCompletionViewModel
//

import XCTest
@testable import AmakaFlowCompanion

@MainActor
final class WorkoutCompletionViewModelTests: XCTestCase {

    // MARK: - Duration Formatting Tests

    func testFormattedDurationMinutesOnly() {
        let viewModel = createViewModel(durationSeconds: 300) // 5 minutes

        XCTAssertEqual(viewModel.formattedDuration, "5m 0s")
    }

    func testFormattedDurationMinutesAndSeconds() {
        let viewModel = createViewModel(durationSeconds: 185) // 3m 5s

        XCTAssertEqual(viewModel.formattedDuration, "3m 5s")
    }

    func testFormattedDurationWithHours() {
        let viewModel = createViewModel(durationSeconds: 3725) // 1h 2m 5s

        XCTAssertEqual(viewModel.formattedDuration, "1h 2m 5s")
    }

    func testFormattedDurationZeroSeconds() {
        let viewModel = createViewModel(durationSeconds: 0)

        XCTAssertEqual(viewModel.formattedDuration, "0m 0s")
    }

    // MARK: - Heart Rate Data Detection Tests

    func testHasHeartRateDataWithAvgHR() {
        let viewModel = createViewModel(avgHeartRate: 140)

        XCTAssertTrue(viewModel.hasHeartRateData)
    }

    func testHasHeartRateDataWithSamples() {
        let samples = createSamples(count: 5, baseValue: 130)
        let viewModel = createViewModel(heartRateSamples: samples)

        XCTAssertTrue(viewModel.hasHeartRateData)
    }

    func testHasHeartRateDataWithBoth() {
        let samples = createSamples(count: 5, baseValue: 130)
        let viewModel = createViewModel(avgHeartRate: 140, heartRateSamples: samples)

        XCTAssertTrue(viewModel.hasHeartRateData)
    }

    func testHasNoHeartRateData() {
        let viewModel = createViewModel()

        XCTAssertFalse(viewModel.hasHeartRateData)
    }

    // MARK: - Avg Heart Rate Calculation Tests

    func testCalculatedAvgHeartRateUsesProvidedValue() {
        let samples = createSamples(count: 5, baseValue: 100)
        let viewModel = createViewModel(avgHeartRate: 150, heartRateSamples: samples)

        // Should use provided avgHeartRate, not calculate from samples
        XCTAssertEqual(viewModel.calculatedAvgHeartRate, 150)
    }

    func testCalculatedAvgHeartRateFromSamples() {
        // Create samples with known values: 100, 120, 140 -> avg = 120
        let samples = [
            HeartRateSample(timestamp: Date(), value: 100),
            HeartRateSample(timestamp: Date(), value: 120),
            HeartRateSample(timestamp: Date(), value: 140)
        ]
        let viewModel = createViewModel(heartRateSamples: samples)

        XCTAssertEqual(viewModel.calculatedAvgHeartRate, 120)
    }

    func testCalculatedAvgHeartRateNoData() {
        let viewModel = createViewModel()

        XCTAssertNil(viewModel.calculatedAvgHeartRate)
    }

    // MARK: - Max Heart Rate Calculation Tests

    func testCalculatedMaxHeartRateUsesProvidedValue() {
        let samples = createSamples(count: 5, baseValue: 100)
        let viewModel = createViewModel(maxHeartRate: 180, heartRateSamples: samples)

        // Should use provided maxHeartRate, not calculate from samples
        XCTAssertEqual(viewModel.calculatedMaxHeartRate, 180)
    }

    func testCalculatedMaxHeartRateFromSamples() {
        let samples = [
            HeartRateSample(timestamp: Date(), value: 100),
            HeartRateSample(timestamp: Date(), value: 175),
            HeartRateSample(timestamp: Date(), value: 140)
        ]
        let viewModel = createViewModel(heartRateSamples: samples)

        XCTAssertEqual(viewModel.calculatedMaxHeartRate, 175)
    }

    func testCalculatedMaxHeartRateNoData() {
        let viewModel = createViewModel()

        XCTAssertNil(viewModel.calculatedMaxHeartRate)
    }

    // MARK: - Edge Cases

    func testSingleSampleAvgAndMax() {
        let samples = [HeartRateSample(timestamp: Date(), value: 142)]
        let viewModel = createViewModel(heartRateSamples: samples)

        XCTAssertEqual(viewModel.calculatedAvgHeartRate, 142)
        XCTAssertEqual(viewModel.calculatedMaxHeartRate, 142)
    }

    func testEmptySamplesReturnsNil() {
        let viewModel = createViewModel(heartRateSamples: [])

        XCTAssertNil(viewModel.calculatedAvgHeartRate)
        XCTAssertNil(viewModel.calculatedMaxHeartRate)
    }

    func testAllNilMetricsHandledGracefully() {
        let viewModel = createViewModel(
            calories: nil,
            avgHeartRate: nil,
            maxHeartRate: nil,
            heartRateSamples: []
        )

        XCTAssertNil(viewModel.calories)
        XCTAssertNil(viewModel.calculatedAvgHeartRate)
        XCTAssertNil(viewModel.calculatedMaxHeartRate)
        XCTAssertFalse(viewModel.hasHeartRateData)
    }

    // MARK: - Toast State Tests

    func testShowComingSoonToastInitiallyFalse() {
        let viewModel = createViewModel()

        XCTAssertFalse(viewModel.showComingSoonToast)
    }

    func testOnViewDetailsShowsToast() {
        let viewModel = createViewModel()

        viewModel.onViewDetails()

        XCTAssertTrue(viewModel.showComingSoonToast)
    }

    // MARK: - Callback Tests

    func testOnDoneCallsDismiss() {
        var dismissCalled = false
        let viewModel = createViewModel(onDismiss: { dismissCalled = true })

        viewModel.onDone()

        XCTAssertTrue(dismissCalled)
    }

    func testOnDoneWithNilDismiss() {
        let viewModel = createViewModel(onDismiss: nil)

        // Should not crash
        viewModel.onDone()
    }

    // MARK: - Helper Methods

    private func createViewModel(
        workoutName: String = "Test Workout",
        durationSeconds: Int = 1800,
        deviceMode: DevicePreference = .phoneOnly,
        calories: Int? = nil,
        avgHeartRate: Int? = nil,
        maxHeartRate: Int? = nil,
        heartRateSamples: [HeartRateSample] = [],
        onDismiss: (() -> Void)? = nil
    ) -> WorkoutCompletionViewModel {
        WorkoutCompletionViewModel(
            workoutName: workoutName,
            durationSeconds: durationSeconds,
            deviceMode: deviceMode,
            calories: calories,
            avgHeartRate: avgHeartRate,
            maxHeartRate: maxHeartRate,
            heartRateSamples: heartRateSamples,
            onDismiss: onDismiss
        )
    }

    private func createSamples(count: Int, baseValue: Int) -> [HeartRateSample] {
        (0..<count).map { i in
            HeartRateSample(
                timestamp: Date().addingTimeInterval(Double(i) * 5),
                value: baseValue + (i * 5)
            )
        }
    }
}
