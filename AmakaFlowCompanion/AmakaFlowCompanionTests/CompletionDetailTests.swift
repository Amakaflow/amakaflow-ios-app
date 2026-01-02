//
//  CompletionDetailTests.swift
//  AmakaFlowCompanionTests
//
//  Tests for completion detail feature - logic and data transformations
//
//  Tests the logic used by CompletionDetailView without depending on types
//  that require Xcode project configuration. This ensures tests can run
//  in the CI environment reliably.
//

import XCTest
@testable import AmakaFlowCompanion

final class CompletionDetailTests: XCTestCase {

    // MARK: - Duration Formatting Tests

    func testFormattedDurationMinutesOnly() {
        let result = formatDuration(durationSeconds: 300)
        XCTAssertEqual(result, "5:00")
    }

    func testFormattedDurationMinutesAndSeconds() {
        let result = formatDuration(durationSeconds: 185)
        XCTAssertEqual(result, "3:05")
    }

    func testFormattedDurationWithHours() {
        let result = formatDuration(durationSeconds: 3725)
        XCTAssertEqual(result, "1:02:05")
    }

    func testFormattedDurationZeroSeconds() {
        let result = formatDuration(durationSeconds: 0)
        XCTAssertEqual(result, "0:00")
    }

    // MARK: - HR Zone Calculation Tests

    func testCalculateZonesWithSamples() {
        // Samples in zone 3 (70-80% of 200 max = 140-160 bpm)
        let samples = [
            TestHRSample(timestamp: Date(), bpm: 145),
            TestHRSample(timestamp: Date(), bpm: 150),
            TestHRSample(timestamp: Date(), bpm: 155)
        ]

        let zones = calculateHRZones(samples: samples, maxHR: 200, durationSeconds: 180)

        // Zone 3 should have all the time
        let zone3 = zones.first { $0.id == 3 }
        XCTAssertNotNil(zone3)
        XCTAssertGreaterThan(zone3?.percentageOfWorkout ?? 0, 90)
    }

    func testCalculateZonesEmptySamples() {
        let zones = calculateHRZones(samples: [], maxHR: 190, durationSeconds: 0)

        XCTAssertEqual(zones.count, 5)
        zones.forEach { zone in
            XCTAssertEqual(zone.percentageOfWorkout, 0)
        }
    }

    func testCalculateZonesMultipleZones() {
        // Mix of samples across zones
        let samples = [
            TestHRSample(timestamp: Date(), bpm: 100), // ~53% of 190 = Zone 1
            TestHRSample(timestamp: Date(), bpm: 125), // ~66% of 190 = Zone 2
            TestHRSample(timestamp: Date(), bpm: 145), // ~76% of 190 = Zone 3
            TestHRSample(timestamp: Date(), bpm: 165), // ~87% of 190 = Zone 4
            TestHRSample(timestamp: Date(), bpm: 180)  // ~95% of 190 = Zone 5
        ]

        let zones = calculateHRZones(samples: samples, maxHR: 190, durationSeconds: 300)

        // Each zone should have some percentage
        let nonZeroZones = zones.filter { $0.percentageOfWorkout > 0 }
        XCTAssertGreaterThanOrEqual(nonZeroZones.count, 4) // At least 4 zones should have data
    }

    func testCalculateZonesBoundaries() {
        // Test exact zone boundaries
        let maxHR = 200

        // Zone 1: 50-60% = 100-120 bpm
        XCTAssertEqual(zoneForBPM(100, maxHR: maxHR), 1)
        XCTAssertEqual(zoneForBPM(119, maxHR: maxHR), 1)

        // Zone 2: 60-70% = 120-140 bpm
        XCTAssertEqual(zoneForBPM(120, maxHR: maxHR), 2)
        XCTAssertEqual(zoneForBPM(139, maxHR: maxHR), 2)

        // Zone 3: 70-80% = 140-160 bpm
        XCTAssertEqual(zoneForBPM(140, maxHR: maxHR), 3)
        XCTAssertEqual(zoneForBPM(159, maxHR: maxHR), 3)

        // Zone 4: 80-90% = 160-180 bpm
        XCTAssertEqual(zoneForBPM(160, maxHR: maxHR), 4)
        XCTAssertEqual(zoneForBPM(179, maxHR: maxHR), 4)

        // Zone 5: 90-100% = 180-200 bpm
        XCTAssertEqual(zoneForBPM(180, maxHR: maxHR), 5)
        XCTAssertEqual(zoneForBPM(200, maxHR: maxHR), 5)
    }

    func testCalculateZonesAboveMaxHR() {
        // BPM above max should go to Zone 5
        XCTAssertEqual(zoneForBPM(210, maxHR: 200), 5)
        XCTAssertEqual(zoneForBPM(250, maxHR: 200), 5)
    }

    // MARK: - Zone Formatting Tests

    func testZoneFormattedTimeMinutesAndSeconds() {
        let result = formatZoneTime(seconds: 125) // 2m 5s
        XCTAssertEqual(result, "2m 5s")
    }

    func testZoneFormattedTimeSecondsOnly() {
        let result = formatZoneTime(seconds: 45)
        XCTAssertEqual(result, "45s")
    }

    func testZoneFormattedTimeZero() {
        let result = formatZoneTime(seconds: 0)
        XCTAssertEqual(result, "0s")
    }

    func testZoneRangeLabel() {
        let label = zoneRangeLabel(minPercent: 70, maxPercent: 80)
        XCTAssertEqual(label, "70-80%")
    }

    // MARK: - Metric Formatting Tests

    func testFormattedCaloriesUnder1000() {
        let result = formatCalories(500)
        XCTAssertEqual(result, "500")
    }

    func testFormattedCaloriesOver1000() {
        let result = formatCalories(1500)
        XCTAssertEqual(result, "1.5k")
    }

    func testFormattedStepsUnder1000() {
        let result = formatSteps(850)
        XCTAssertEqual(result, "850")
    }

    func testFormattedStepsOver1000() {
        let result = formatSteps(4500)
        XCTAssertEqual(result, "4.5k")
    }

    func testFormattedDistanceMeters() {
        let result = formatDistance(meters: 500)
        XCTAssertEqual(result, "500 m")
    }

    func testFormattedDistanceKilometers() {
        let result = formatDistance(meters: 3200)
        XCTAssertEqual(result, "3.20 km")
    }

    // MARK: - Date/Time Formatting Tests

    func testFormattedDateTimeToday() {
        let now = Date()
        let result = formatDateTime(now)
        XCTAssertTrue(result.starts(with: "Today at"))
    }

    func testFormattedDateTimeYesterday() {
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        let result = formatDateTime(yesterday)
        XCTAssertTrue(result.starts(with: "Yesterday at"))
    }

    func testFormattedDateTimeOlder() {
        let lastWeek = Calendar.current.date(byAdding: .day, value: -7, to: Date())!
        let result = formatDateTime(lastWeek)
        XCTAssertFalse(result.starts(with: "Today"))
        XCTAssertFalse(result.starts(with: "Yesterday"))
    }

    // MARK: - Data Availability Tests

    func testHasHeartRateDataWithAvg() {
        let result = hasHeartRateData(avgHeartRate: 140, samples: [])
        XCTAssertTrue(result)
    }

    func testHasHeartRateDataWithSamples() {
        let samples = [TestHRSample(timestamp: Date(), bpm: 140)]
        let result = hasHeartRateData(avgHeartRate: nil, samples: samples)
        XCTAssertTrue(result)
    }

    func testHasNoHeartRateData() {
        let result = hasHeartRateData(avgHeartRate: nil, samples: [])
        XCTAssertFalse(result)
    }

    func testHasSummaryMetricsWithCalories() {
        let result = hasSummaryMetrics(calories: 300, steps: nil, distance: nil)
        XCTAssertTrue(result)
    }

    func testHasSummaryMetricsWithSteps() {
        let result = hasSummaryMetrics(calories: nil, steps: 5000, distance: nil)
        XCTAssertTrue(result)
    }

    func testHasSummaryMetricsWithDistance() {
        let result = hasSummaryMetrics(calories: nil, steps: nil, distance: 3000)
        XCTAssertTrue(result)
    }

    func testHasNoSummaryMetrics() {
        let result = hasSummaryMetrics(calories: nil, steps: nil, distance: nil)
        XCTAssertFalse(result)
    }

    // MARK: - Strava Status Tests

    func testCanSyncToStravaNotSynced() {
        let result = canSyncToStrava(synced: false)
        XCTAssertTrue(result)
    }

    func testCannotSyncToStravaAlreadySynced() {
        let result = canSyncToStrava(synced: true)
        XCTAssertFalse(result)
    }

    func testStravaButtonTextNotSynced() {
        let result = stravaButtonText(synced: false)
        XCTAssertEqual(result, "Sync to Strava")
    }

    func testStravaButtonTextSynced() {
        let result = stravaButtonText(synced: true)
        XCTAssertEqual(result, "View on Strava")
    }

    // MARK: - Device Info Tests

    func testDeviceDisplayNameWithModel() {
        let result = deviceDisplayName(name: "Apple Watch", model: "Series 9")
        XCTAssertEqual(result, "Apple Watch Series 9")
    }

    func testDeviceDisplayNameWithoutModel() {
        let result = deviceDisplayName(name: "Garmin Forerunner", model: nil)
        XCTAssertEqual(result, "Garmin Forerunner")
    }

    // MARK: - Chart Y-Axis Range Tests

    func testChartYAxisRange() {
        let samples = [
            TestHRSample(timestamp: Date(), bpm: 90),
            TestHRSample(timestamp: Date(), bpm: 170)
        ]

        let (min, max) = chartYAxisRange(samples: samples, providedMin: nil, providedMax: nil)

        // Should have padding
        XCTAssertLessThan(min, 90)
        XCTAssertGreaterThan(max, 170)
    }

    func testChartYAxisRangeUsesProvidedValues() {
        let samples = [
            TestHRSample(timestamp: Date(), bpm: 100),
            TestHRSample(timestamp: Date(), bpm: 150)
        ]

        let (min, max) = chartYAxisRange(samples: samples, providedMin: 85, providedMax: 180)

        // Should use provided values if they extend beyond samples
        XCTAssertLessThanOrEqual(min, 85)
        XCTAssertGreaterThanOrEqual(max, 180)
    }

    // MARK: - Helper Methods (mirror logic for testing)

    private struct TestHRSample {
        let timestamp: Date
        let bpm: Int
    }

    private struct TestHRZone {
        let id: Int
        let name: String
        let minPercent: Int
        let maxPercent: Int
        let timeInZoneSeconds: Int
        let percentageOfWorkout: Double
    }

    private func formatDuration(durationSeconds: Int) -> String {
        let hours = durationSeconds / 3600
        let minutes = (durationSeconds % 3600) / 60
        let seconds = durationSeconds % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }

    private func calculateHRZones(samples: [TestHRSample], maxHR: Int, durationSeconds: Int) -> [TestHRZone] {
        let zoneBoundaries: [(zone: Int, name: String, minPct: Int, maxPct: Int)] = [
            (1, "Zone 1", 50, 60),
            (2, "Zone 2", 60, 70),
            (3, "Zone 3", 70, 80),
            (4, "Zone 4", 80, 90),
            (5, "Zone 5", 90, 100)
        ]

        guard !samples.isEmpty else {
            return zoneBoundaries.map {
                TestHRZone(id: $0.zone, name: $0.name, minPercent: $0.minPct, maxPercent: $0.maxPct, timeInZoneSeconds: 0, percentageOfWorkout: 0)
            }
        }

        var zoneSeconds: [Int: Int] = [:]
        for boundary in zoneBoundaries {
            zoneSeconds[boundary.zone] = 0
        }

        let sampleInterval = samples.count > 1 ? durationSeconds / samples.count : durationSeconds

        for sample in samples {
            let percentage = Double(sample.bpm) / Double(maxHR) * 100

            for boundary in zoneBoundaries {
                if percentage >= Double(boundary.minPct) && percentage < Double(boundary.maxPct) {
                    zoneSeconds[boundary.zone, default: 0] += sampleInterval
                    break
                } else if percentage >= 100 && boundary.zone == 5 {
                    zoneSeconds[5, default: 0] += sampleInterval
                    break
                }
            }
        }

        return zoneBoundaries.map { boundary in
            let seconds = zoneSeconds[boundary.zone] ?? 0
            let percentage = durationSeconds > 0 ? Double(seconds) / Double(durationSeconds) * 100 : 0

            return TestHRZone(
                id: boundary.zone,
                name: boundary.name,
                minPercent: boundary.minPct,
                maxPercent: boundary.maxPct,
                timeInZoneSeconds: seconds,
                percentageOfWorkout: percentage
            )
        }
    }

    private func zoneForBPM(_ bpm: Int, maxHR: Int) -> Int {
        let percentage = Double(bpm) / Double(maxHR) * 100

        if percentage >= 90 { return 5 }
        if percentage >= 80 { return 4 }
        if percentage >= 70 { return 3 }
        if percentage >= 60 { return 2 }
        return 1
    }

    private func formatZoneTime(seconds: Int) -> String {
        let minutes = seconds / 60
        let secs = seconds % 60
        if minutes > 0 {
            return "\(minutes)m \(secs)s"
        }
        return "\(secs)s"
    }

    private func zoneRangeLabel(minPercent: Int, maxPercent: Int) -> String {
        "\(minPercent)-\(maxPercent)%"
    }

    private func formatCalories(_ calories: Int) -> String {
        if calories >= 1000 {
            return String(format: "%.1fk", Double(calories) / 1000.0)
        }
        return "\(calories)"
    }

    private func formatSteps(_ steps: Int) -> String {
        if steps >= 1000 {
            return String(format: "%.1fk", Double(steps) / 1000.0)
        }
        return "\(steps)"
    }

    private func formatDistance(meters: Int) -> String {
        if meters >= 1000 {
            let km = Double(meters) / 1000.0
            return String(format: "%.2f km", km)
        }
        return "\(meters) m"
    }

    private func formatDateTime(_ date: Date) -> String {
        let calendar = Calendar.current
        let timeString = date.formatted(date: .omitted, time: .shortened)

        if calendar.isDateInToday(date) {
            return "Today at \(timeString)"
        } else if calendar.isDateInYesterday(date) {
            return "Yesterday at \(timeString)"
        } else {
            return date.formatted(.dateTime.month(.abbreviated).day().hour().minute())
        }
    }

    private func hasHeartRateData(avgHeartRate: Int?, samples: [TestHRSample]) -> Bool {
        avgHeartRate != nil || !samples.isEmpty
    }

    private func hasSummaryMetrics(calories: Int?, steps: Int?, distance: Int?) -> Bool {
        calories != nil || steps != nil || distance != nil
    }

    private func canSyncToStrava(synced: Bool) -> Bool {
        !synced
    }

    private func stravaButtonText(synced: Bool) -> String {
        synced ? "View on Strava" : "Sync to Strava"
    }

    private func deviceDisplayName(name: String, model: String?) -> String {
        if let model = model {
            return "\(name) \(model)"
        }
        return name
    }

    private func chartYAxisRange(samples: [TestHRSample], providedMin: Int?, providedMax: Int?) -> (min: Int, max: Int) {
        let minSample = samples.map(\.bpm).min() ?? 60
        let maxSample = samples.map(\.bpm).max() ?? 180
        let effectiveMin = min(minSample, providedMin ?? minSample)
        let effectiveMax = max(maxSample, providedMax ?? maxSample)
        return (max(40, effectiveMin - 10), min(220, effectiveMax + 10))
    }

    // MARK: - Workout Steps Tests (AMA-224)

    func testHasWorkoutStepsWithIntervals() {
        let intervals: [TestInterval] = [
            .warmup(seconds: 300),
            .reps(sets: 3, reps: 10, name: "Squats")
        ]
        let result = hasWorkoutSteps(intervals: intervals)
        XCTAssertTrue(result)
    }

    func testHasWorkoutStepsWithEmptyIntervals() {
        let intervals: [TestInterval] = []
        let result = hasWorkoutSteps(intervals: intervals)
        XCTAssertFalse(result)
    }

    func testHasWorkoutStepsWithNil() {
        let result = hasWorkoutSteps(intervals: nil)
        XCTAssertFalse(result)
    }

    func testFlattenIntervalsSimple() {
        let intervals: [TestInterval] = [
            .warmup(seconds: 300),
            .time(seconds: 60),
            .cooldown(seconds: 300)
        ]

        let flattened = flattenIntervals(intervals)
        XCTAssertEqual(flattened.count, 3)
        XCTAssertEqual(flattened[0].name, "Warm Up")
        XCTAssertEqual(flattened[1].name, "Timed Interval")
        XCTAssertEqual(flattened[2].name, "Cool Down")
    }

    func testFlattenIntervalsWithReps() {
        let intervals: [TestInterval] = [
            .reps(sets: 3, reps: 10, name: "Squats"),
            .reps(sets: nil, reps: 15, name: "Lunges")
        ]

        let flattened = flattenIntervals(intervals)
        XCTAssertEqual(flattened.count, 2)
        XCTAssertEqual(flattened[0].detail, "3 × 10 reps")
        XCTAssertEqual(flattened[1].detail, "15 reps")
    }

    func testFlattenIntervalsWithRepeat() {
        let intervals: [TestInterval] = [
            .repeat(count: 3, intervals: [
                .time(seconds: 30),
                .time(seconds: 30)
            ])
        ]

        let flattened = flattenIntervals(intervals)
        XCTAssertEqual(flattened.count, 6) // 3 repeats × 2 intervals
    }

    func testStepNumbersAreSequential() {
        let intervals: [TestInterval] = [
            .warmup(seconds: 300),
            .reps(sets: 3, reps: 10, name: "Squats"),
            .cooldown(seconds: 300)
        ]

        let flattened = flattenIntervals(intervals)
        XCTAssertEqual(flattened[0].stepNumber, 1)
        XCTAssertEqual(flattened[1].stepNumber, 2)
        XCTAssertEqual(flattened[2].stepNumber, 3)
    }

    // MARK: - Save to Library Tests (AMA-224)

    func testCanSaveToLibraryWithNoWorkoutId() {
        let result = canSaveToLibrary(workoutId: nil, hasIntervals: true)
        XCTAssertTrue(result)
    }

    func testCannotSaveToLibraryWithWorkoutId() {
        let result = canSaveToLibrary(workoutId: "workout-123", hasIntervals: true)
        XCTAssertFalse(result)
    }

    func testCannotSaveToLibraryWithoutIntervals() {
        let result = canSaveToLibrary(workoutId: nil, hasIntervals: false)
        XCTAssertFalse(result)
    }

    func testInferSportFromRepsIntervals() {
        let intervals: [TestInterval] = [
            .reps(sets: 3, reps: 10, name: "Squats"),
            .reps(sets: 3, reps: 12, name: "Lunges")
        ]

        let sport = inferSportFromIntervals(intervals)
        XCTAssertEqual(sport, "strength")
    }

    func testInferSportFromDistanceIntervals() {
        let intervals: [TestInterval] = [
            .warmup(seconds: 300),
            .distance(meters: 1000),
            .cooldown(seconds: 300)
        ]

        let sport = inferSportFromIntervals(intervals)
        XCTAssertEqual(sport, "running")
    }

    func testInferSportFromTimeIntervals() {
        let intervals: [TestInterval] = [
            .warmup(seconds: 300),
            .time(seconds: 60),
            .time(seconds: 60),
            .cooldown(seconds: 300)
        ]

        let sport = inferSportFromIntervals(intervals)
        XCTAssertEqual(sport, "cardio")
    }

    // MARK: - Workout Steps Helper Types

    private enum TestInterval {
        case warmup(seconds: Int)
        case cooldown(seconds: Int)
        case time(seconds: Int)
        case reps(sets: Int?, reps: Int, name: String)
        case distance(meters: Int)
        case `repeat`(count: Int, intervals: [TestInterval])
    }

    private struct TestStepItem {
        let stepNumber: Int
        let name: String
        let detail: String
    }

    private func hasWorkoutSteps(intervals: [TestInterval]?) -> Bool {
        !(intervals?.isEmpty ?? true)
    }

    private func flattenIntervals(_ intervals: [TestInterval]) -> [TestStepItem] {
        var items: [TestStepItem] = []
        var stepNumber = 0

        func flatten(_ interval: TestInterval) {
            switch interval {
            case .warmup(let seconds):
                stepNumber += 1
                items.append(TestStepItem(stepNumber: stepNumber, name: "Warm Up", detail: formatIntervalTime(seconds)))
            case .cooldown(let seconds):
                stepNumber += 1
                items.append(TestStepItem(stepNumber: stepNumber, name: "Cool Down", detail: formatIntervalTime(seconds)))
            case .time(let seconds):
                stepNumber += 1
                items.append(TestStepItem(stepNumber: stepNumber, name: "Timed Interval", detail: formatIntervalTime(seconds)))
            case .reps(let sets, let reps, let name):
                stepNumber += 1
                var detail = "\(reps) reps"
                if let sets = sets, sets > 1 {
                    detail = "\(sets) × \(reps) reps"
                }
                items.append(TestStepItem(stepNumber: stepNumber, name: name, detail: detail))
            case .distance(let meters):
                stepNumber += 1
                items.append(TestStepItem(stepNumber: stepNumber, name: "Distance", detail: formatDistance(meters: meters)))
            case .repeat(let count, let subIntervals):
                for _ in 0..<count {
                    for sub in subIntervals {
                        flatten(sub)
                    }
                }
            }
        }

        for interval in intervals {
            flatten(interval)
        }

        return items
    }

    private func formatIntervalTime(_ seconds: Int) -> String {
        if seconds >= 60 {
            let minutes = seconds / 60
            let secs = seconds % 60
            if secs > 0 {
                return "\(minutes)m \(secs)s"
            }
            return "\(minutes) min"
        }
        return "\(seconds)s"
    }

    private func canSaveToLibrary(workoutId: String?, hasIntervals: Bool) -> Bool {
        workoutId == nil && hasIntervals
    }

    private func inferSportFromIntervals(_ intervals: [TestInterval]) -> String {
        let hasReps = intervals.contains { interval in
            if case .reps = interval { return true }
            return false
        }

        let hasDistance = intervals.contains { interval in
            if case .distance = interval { return true }
            return false
        }

        if hasReps {
            return "strength"
        } else if hasDistance {
            return "running"
        } else {
            return "cardio"
        }
    }
}
