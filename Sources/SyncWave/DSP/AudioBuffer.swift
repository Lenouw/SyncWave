import Foundation
import Accelerate

/// Wrapper around a Float32 PCM buffer at a known sample rate.
struct AudioBuffer {
    let samples: [Float]
    let sampleRate: Double
    let channelCount: Int

    var duration: TimeInterval {
        Double(samples.count) / sampleRate / Double(channelCount)
    }

    var sampleCount: Int { samples.count }

    /// Downsample to a target sample rate using simple decimation.
    func downsampled(to targetRate: Double) -> AudioBuffer {
        guard targetRate < sampleRate else { return self }
        let ratio = Int(sampleRate / targetRate)
        let newCount = samples.count / ratio
        var output = [Float](repeating: 0, count: newCount)
        for i in 0..<newCount {
            output[i] = samples[i * ratio]
        }
        return AudioBuffer(samples: output, sampleRate: targetRate, channelCount: 1)
    }

    /// Extract a window of samples around a center position (in seconds).
    func window(centerSeconds: TimeInterval, windowSeconds: TimeInterval) -> AudioBuffer {
        let centerSample = Int(centerSeconds * sampleRate)
        let halfWindow = Int(windowSeconds * sampleRate / 2)
        let start = max(0, centerSample - halfWindow)
        let end = min(samples.count, centerSample + halfWindow)
        guard start < end else {
            return AudioBuffer(samples: [], sampleRate: sampleRate, channelCount: 1)
        }
        let slice = Array(samples[start..<end])
        return AudioBuffer(samples: slice, sampleRate: sampleRate, channelCount: 1)
    }
}
