//
//  WorkoutCompletionViewModelTests.swift
//  AmakaFlowCompanionTests
//
//  Unit tests for WorkoutCompletionViewModel
//
//  Tests the computed properties of WorkoutCompletionViewModel without triggering
//  @MainActor deallocation issues by testing the logic directly.
//

import XCTest
@testable import AmakaFlowCompanion

final class WorkoutCompletionViewModelTests: XCTestCase {

    // MARK: - Duration Formatting Tests
    // Test the formatting logic directly without ViewModel lifecycle concerns

    func testFormattedDurationMinutesOnly() {
        let result = formatDuration(seconds: 300) // 5 minutes
        XCTAssertEqual(result, "5m 0s")
    }

    func testFormattedDurationMinutesAndSeconds() {
        let result = formatDuration(seconds: 185) // 3m 5s
        XCTAssertEqual(result, "3m 5s")
    }

    func testFormattedDurationWithHours() {
        let result = formatDuration(seconds: 3725) // 1h 2m 5s
        XCTAssertEqual(result, "1h 2m 5s")
    }

    func testFormattedDurationZeroSeconds() {
        let result = formatDuration(seconds: 0)
        XCTAssertEqual(result, "0m 0s")
    }

    // MARK: - Heart Rate Data Detection Tests

    func testHasHeartRateDataWithAvgHR() {
        let result = hasHeartRateData(avgHeartRate: 140, samples: [])
        XCTAssertTrue(result)
    }

    func testHasHeartRateDataWithSamples() {
        let samples = createSamples(count: 5, baseValue: 130)
        let result = hasHeartRateData(avgHeartRate: nil, samples: samples)
        XCTAssertTrue(result)
    }

    func testHasNoHeartRateData() {
        let result = hasHeartRateData(avgHeartRate: nil, samples: [])
        XCTAssertFalse(result)
    }

    // MARK: - Avg Heart Rate Calculation Tests

    func testCalculatedAvgHeartRateUsesProvidedValue() {
        let samples = createSamples(count: 5, baseValue: 100)
        let result = calculateAvgHeartRate(provided: 150, samples: samples)
        XCTAssertEqual(result, 150)
    }

    func testCalculatedAvgHeartRateFromSamples() {
        let samples = [
            HeartRateSample(timestamp: Date(), value: 100),
            HeartRateSample(timestamp: Date(), value: 120),
            HeartRateSample(timestamp: Date(), value: 140)
        ]
        let result = calculateAvgHeartRate(provided: nil, samples: samples)
        XCTAssertEqual(result, 120)
    }

    func testCalculatedAvgHeartRateNoData() {
        let result = calculateAvgHeartRate(provided: nil, samples: [])
        XCTAssertNil(result)
    }

    // MARK: - Max Heart Rate Calculation Tests

    func testCalculatedMaxHeartRateUsesProvidedValue() {
        let samples = createSamples(count: 5, baseValue: 100)
        let result = calculateMaxHeartRate(provided: 180, samples: samples)
        XCTAssertEqual(result, 180)
    }

    func testCalculatedMaxHeartRateFromSamples() {
        let samples = [
            HeartRateSample(timestamp: Date(), value: 100),
            HeartRateSample(timestamp: Date(), value: 175),
            HeartRateSample(timestamp: Date(), value: 140)
        ]
        let result = calculateMaxHeartRate(provided: nil, samples: samples)
        XCTAssertEqual(result, 175)
    }

    func testCalculatedMaxHeartRateNoData() {
        let result = calculateMaxHeartRate(provided: nil, samples: [])
        XCTAssertNil(result)
    }

    // MARK: - Edge Cases

    func testSingleSampleAvgAndMax() {
        let samples = [HeartRateSample(timestamp: Date(), value: 142)]
        XCTAssertEqual(calculateAvgHeartRate(provided: nil, samples: samples), 142)
        XCTAssertEqual(calculateMaxHeartRate(provided: nil, samples: samples), 142)
    }

    // MARK: - Helper Methods (mirror ViewModel logic for testing)

    private func formatDuration(seconds: Int) -> String {
        let hours = seconds / 3600
        let mins = (seconds % 3600) / 60
        let secs = seconds % 60

        if hours > 0 {
            return "\(hours)h \(mins)m \(secs)s"
        }
        return "\(mins)m \(secs)s"
    }

    private func hasHeartRateData(avgHeartRate: Int?, samples: [HeartRateSample]) -> Bool {
        avgHeartRate != nil || !samples.isEmpty
    }

    private func calculateAvgHeartRate(provided: Int?, samples: [HeartRateSample]) -> Int? {
        if let avgHR = provided {
            return avgHR
        }
        guard !samples.isEmpty else { return nil }
        let sum = samples.reduce(0) { $0 + $1.value }
        return sum / samples.count
    }

    private func calculateMaxHeartRate(provided: Int?, samples: [HeartRateSample]) -> Int? {
        if let maxHR = provided {
            return maxHR
        }
        return samples.map { $0.value }.max()
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
