import Foundation

struct RepSegmenter {
    let windowSize: Int
    private let minRepSamples: Int = 20
    private let peakThreshold: Float = 0.3

    init(windowSize: Int = 200) {
        self.windowSize = windowSize
    }

    /// Extract rep windows from IMU buffer.
    /// A "rep" is the segment between two consecutive Y-axis peaks (standing positions).
    /// Returns an array of [IMUSample] windows, each padded/trimmed to windowSize.
    func extractReps(from samples: [IMUSample]) -> [[IMUSample]] {
        guard samples.count >= minRepSamples * 2 else { return [] }

        let yValues = samples.map { $0.accY }
        let peaks = findPeaks(in: yValues, minDistance: minRepSamples)
        guard peaks.count >= 2 else { return [] }

        return zip(peaks, peaks.dropFirst()).map { start, end in
            resample(Array(samples[start..<end]), to: windowSize)
        }
    }

    // MARK: - Private

    /// Find peak indices in signal.
    /// A peak is the last sample of a local maximum region (plateau or spike)
    /// that exceeds peakThreshold and is separated from the previous peak by
    /// at least minDistance samples.
    private func findPeaks(in signal: [Float], minDistance: Int) -> [Int] {
        var peaks: [Int] = []
        var lastPeak = -minDistance
        var i = 1

        while i < signal.count {
            guard signal[i] > peakThreshold else {
                i += 1
                continue
            }
            // We are in a region above threshold.
            // Walk forward to find the end of the plateau.
            var j = i
            while j + 1 < signal.count && signal[j + 1] >= signal[j] {
                j += 1
            }
            // j is now the index of the last non-decreasing sample in this run.
            // It qualifies as a peak if the next sample is strictly lower (descent)
            // or if j is the last sample.
            let isEdgePeak = (j == signal.count - 1) || (signal[j + 1] < signal[j])
            if isEdgePeak && signal[j] > peakThreshold && (j - lastPeak) >= minDistance {
                peaks.append(j)
                lastPeak = j
            }
            i = j + 1
        }
        return peaks
    }

    /// Pad or trim segment to exactly `size` samples.
    private func resample(_ segment: [IMUSample], to size: Int) -> [IMUSample] {
        if segment.count == size { return segment }
        if segment.count > size { return Array(segment.prefix(size)) }
        let padding = Array(repeating: segment.last!, count: size - segment.count)
        return segment + padding
    }
}
