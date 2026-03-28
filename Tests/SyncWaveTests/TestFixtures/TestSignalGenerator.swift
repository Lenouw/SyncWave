import Foundation
@testable import SyncWave

/// Generates synthetic audio signals for testing the sync engine.
struct TestSignalGenerator {

    /// Generate a sine wave signal.
    static func sineWave(
        frequency: Double,
        sampleRate: Double,
        duration: TimeInterval
    ) -> AudioBuffer {
        let sampleCount = Int(sampleRate * duration)
        var samples = [Float](repeating: 0, count: sampleCount)
        for i in 0..<sampleCount {
            let t = Double(i) / sampleRate
            samples[i] = Float(sin(2.0 * .pi * frequency * t))
        }
        return AudioBuffer(samples: samples, sampleRate: sampleRate, channelCount: 1)
    }

    /// Generate a reference signal with mixed frequencies (simulates speech/noise).
    static func complexSignal(
        sampleRate: Double,
        duration: TimeInterval
    ) -> AudioBuffer {
        let sampleCount = Int(sampleRate * duration)
        var samples = [Float](repeating: 0, count: sampleCount)
        let frequencies: [Double] = [220, 440, 660, 1000, 1500, 2200]
        for i in 0..<sampleCount {
            let t = Double(i) / sampleRate
            var value: Float = 0
            for freq in frequencies {
                value += Float(sin(2.0 * .pi * freq * t + freq))
            }
            samples[i] = value / Float(frequencies.count)
        }
        return AudioBuffer(samples: samples, sampleRate: sampleRate, channelCount: 1)
    }

    /// Create a delayed copy of a signal. offsetSamples > 0 means copy starts later.
    static func delayedCopy(
        of buffer: AudioBuffer,
        offsetSamples: Int
    ) -> AudioBuffer {
        if offsetSamples >= 0 {
            let padding = [Float](repeating: 0, count: offsetSamples)
            let trimmed = Array(buffer.samples.prefix(buffer.sampleCount - offsetSamples))
            return AudioBuffer(samples: padding + trimmed, sampleRate: buffer.sampleRate, channelCount: 1)
        } else {
            let skip = abs(offsetSamples)
            let remaining = Array(buffer.samples.dropFirst(skip))
            let padding = [Float](repeating: 0, count: skip)
            return AudioBuffer(samples: remaining + padding, sampleRate: buffer.sampleRate, channelCount: 1)
        }
    }

    /// Create a copy with clock drift. driftPPM > 0 means copy runs slightly faster.
    static func driftedCopy(
        of buffer: AudioBuffer,
        driftPPM: Double
    ) -> AudioBuffer {
        let ratio = 1.0 + (driftPPM / 1_000_000.0)
        let newCount = Int(Double(buffer.sampleCount) / ratio)
        var output = [Float](repeating: 0, count: newCount)
        for i in 0..<newCount {
            let srcIndex = Double(i) * ratio
            let idx = Int(srcIndex)
            if idx + 1 < buffer.sampleCount {
                let frac = Float(srcIndex - Double(idx))
                output[i] = buffer.samples[idx] * (1 - frac) + buffer.samples[idx + 1] * frac
            } else if idx < buffer.sampleCount {
                output[i] = buffer.samples[idx]
            }
        }
        return AudioBuffer(samples: output, sampleRate: buffer.sampleRate, channelCount: 1)
    }
}
