//
//  WorkRestMotionMetrics.swift
//  AmakaFlowWatch Watch App
//
//  AMA-2420 Phase 4 — derive motion energy from FormFeedback IMU samples.
//

import Foundation

enum WorkRestMotionMetrics {
    /// Mean user-acceleration magnitude for the trailing window.
    static func meanAccelerationMagnitude(from samples: [IMUSample]) -> Double {
        guard !samples.isEmpty else { return 0 }
        let sum = samples.reduce(0.0) { partial, sample in
            let mag = sqrt(
                Double(sample.accX * sample.accX)
                    + Double(sample.accY * sample.accY)
                    + Double(sample.accZ * sample.accZ)
            )
            return partial + mag
        }
        return sum / Double(samples.count)
    }

    /// Mean rotation-rate magnitude — secondary cue for arm/wrist work.
    static func meanGyroMagnitude(from samples: [IMUSample]) -> Double {
        guard !samples.isEmpty else { return 0 }
        let sum = samples.reduce(0.0) { partial, sample in
            let mag = sqrt(
                Double(sample.gyrX * sample.gyrX)
                    + Double(sample.gyrY * sample.gyrY)
                    + Double(sample.gyrZ * sample.gyrZ)
            )
            return partial + mag
        }
        return sum / Double(samples.count)
    }

    /// Combined 0…1-ish activity score (not a calibrated probability).
    static func activityScore(from samples: [IMUSample]) -> Double {
        let accel = meanAccelerationMagnitude(from: samples)
        let gyro = meanGyroMagnitude(from: samples)
        // Typical resting wrist motion is near 0; working sets often >0.15–0.4 g.
        let accelNorm = min(1.0, accel / 0.35)
        let gyroNorm = min(1.0, gyro / 1.2)
        return min(1.0, (accelNorm * 0.75) + (gyroNorm * 0.25))
    }
}
