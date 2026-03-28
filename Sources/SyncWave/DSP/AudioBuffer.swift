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

    /// Remove DC offset (subtract mean)
    func removeDCOffset() -> AudioBuffer {
        var mean: Float = 0
        vDSP_meanv(samples, 1, &mean, vDSP_Length(sampleCount))
        var result = [Float](repeating: 0, count: sampleCount)
        var negMean = -mean
        vDSP_vsadd(samples, 1, &negMean, &result, 1, vDSP_Length(sampleCount))
        return AudioBuffer(samples: result, sampleRate: sampleRate, channelCount: channelCount)
    }

    /// Normalize to unit RMS
    func normalized() -> AudioBuffer {
        var rms: Float = 0
        vDSP_rmsqv(samples, 1, &rms, vDSP_Length(sampleCount))
        guard rms > 1e-10 else { return self }
        var scale = 1.0 / rms
        var result = [Float](repeating: 0, count: sampleCount)
        vDSP_vsmul(samples, 1, &scale, &result, 1, vDSP_Length(sampleCount))
        return AudioBuffer(samples: result, sampleRate: sampleRate, channelCount: channelCount)
    }

    /// Apply a simple bandpass filter (300-3000 Hz) using biquad cascades
    func bandpassFiltered(lowFreq: Double = 300, highFreq: Double = 3000) -> AudioBuffer {
        let filtered = applyHighPass(frequency: lowFreq)
        return filtered.applyLowPass(frequency: highFreq)
    }

    private func applyHighPass(frequency: Double) -> AudioBuffer {
        let omega = 2.0 * Double.pi * frequency / sampleRate
        let alpha = sin(omega) / (2.0 * 0.7071) // Q = 0.7071 for Butterworth
        let cosOmega = cos(omega)

        let a0 = Float(1.0 + alpha)
        let b0 = Float((1.0 + cosOmega) / 2.0) / a0
        let b1 = Float(-(1.0 + cosOmega)) / a0
        let b2 = Float((1.0 + cosOmega) / 2.0) / a0
        let a1 = Float(-2.0 * cosOmega) / a0
        let a2 = Float(1.0 - alpha) / a0

        return applyBiquad(b0: b0, b1: b1, b2: b2, a1: a1, a2: a2)
    }

    private func applyLowPass(frequency: Double) -> AudioBuffer {
        let omega = 2.0 * Double.pi * frequency / sampleRate
        let alpha = sin(omega) / (2.0 * 0.7071)
        let cosOmega = cos(omega)

        let a0 = Float(1.0 + alpha)
        let b0 = Float((1.0 - cosOmega) / 2.0) / a0
        let b1 = Float(1.0 - cosOmega) / a0
        let b2 = Float((1.0 - cosOmega) / 2.0) / a0
        let a1 = Float(-2.0 * cosOmega) / a0
        let a2 = Float(1.0 - alpha) / a0

        return applyBiquad(b0: b0, b1: b1, b2: b2, a1: a1, a2: a2)
    }

    private func applyBiquad(b0: Float, b1: Float, b2: Float, a1: Float, a2: Float) -> AudioBuffer {
        var output = [Float](repeating: 0, count: sampleCount)
        var x1: Float = 0, x2: Float = 0
        var y1: Float = 0, y2: Float = 0

        for i in 0..<sampleCount {
            let x0 = samples[i]
            let y0 = b0 * x0 + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
            output[i] = y0
            x2 = x1; x1 = x0
            y2 = y1; y1 = y0
        }

        return AudioBuffer(samples: output, sampleRate: sampleRate, channelCount: channelCount)
    }

    /// Compute RMS energy envelope with given window and hop size (in seconds)
    func energyEnvelope(windowSeconds: Double = 0.02, hopSeconds: Double = 0.005) -> AudioBuffer {
        let windowSize = Int(windowSeconds * sampleRate)
        let hopSize = Int(hopSeconds * sampleRate)
        guard windowSize > 0, hopSize > 0 else { return self }

        let outputCount = (sampleCount - windowSize) / hopSize + 1
        guard outputCount > 0 else { return self }

        var envelope = [Float](repeating: 0, count: outputCount)
        for i in 0..<outputCount {
            let start = i * hopSize
            let end = min(start + windowSize, sampleCount)
            var rms: Float = 0
            let slice = Array(samples[start..<end])
            vDSP_rmsqv(slice, 1, &rms, vDSP_Length(end - start))
            envelope[i] = rms
        }

        let envelopeRate = sampleRate / Double(hopSize)
        return AudioBuffer(samples: envelope, sampleRate: envelopeRate, channelCount: 1)
    }
}
