import Foundation
import Combine
import CoreMotion

struct IMUSample {
    let accX, accY, accZ: Float
    let gyrX, gyrY, gyrZ: Float
    let timestamp: TimeInterval
}

@MainActor
final class MotionCapture: ObservableObject {
    let sampleRate: Double
    private let maxBufferSize: Int
    private let motionManager = CMMotionManager()

    @Published private(set) var buffer: [IMUSample] = []
    @Published private(set) var isCapturing = false

    init(sampleRate: Double = 100.0, maxBufferSize: Int = 600) {
        self.sampleRate = sampleRate
        self.maxBufferSize = maxBufferSize
    }

    func appendSample(_ sample: IMUSample) {
        buffer.append(sample)
        if buffer.count > maxBufferSize {
            buffer.removeFirst(buffer.count - maxBufferSize)
        }
    }

    func startCapture() {
        guard motionManager.isDeviceMotionAvailable else { return }
        motionManager.deviceMotionUpdateInterval = 1.0 / sampleRate
        isCapturing = true   // set before handler can fire
        motionManager.startDeviceMotionUpdates(to: .main) { [weak self] motion, error in
            guard let self, let motion, error == nil else { return }
            let sample = IMUSample(
                accX: Float(motion.userAcceleration.x),
                accY: Float(motion.userAcceleration.y),
                accZ: Float(motion.userAcceleration.z),
                gyrX: Float(motion.rotationRate.x),
                gyrY: Float(motion.rotationRate.y),
                gyrZ: Float(motion.rotationRate.z),
                timestamp: motion.timestamp
            )
            self.appendSample(sample)
        }
    }

    func stopCapture() {
        motionManager.stopDeviceMotionUpdates()
        isCapturing = false
    }
}
