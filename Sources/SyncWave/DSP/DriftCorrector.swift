// Sources/SyncWave/DSP/DriftCorrector.swift
import Foundation
import Accelerate

struct DriftResult {
    let baseOffset: TimeInterval
    let driftPPM: Double
    let windowOffsets: [(time: Double, offset: Double)]
}

struct DriftCorrector {
    let windowSeconds: TimeInterval
    let overlapRatio: Double

    init(windowSeconds: TimeInterval = 30, overlapRatio: Double = 0.5) {
        self.windowSeconds = windowSeconds
        self.overlapRatio = overlapRatio
    }

    func detectDrift(reference: AudioBuffer, target: AudioBuffer) throws -> DriftResult {
        let hopSeconds = windowSeconds * (1.0 - overlapRatio)
        let totalDuration = min(reference.duration, target.duration)
        let sr = reference.sampleRate

        // Drift detection via fine lag search:
        // For each window at time T, extract a short anchor segment from the reference.
        // Search the target around T over a small lag range (±maxSearchSamples).
        // The lag yielding maximum normalized cross-correlation is the accumulated drift at T.
        // Fit a line to (time, accumulatedDrift) to extract driftPPM = slope * 1e6.

        // maxSearchSamples: must cover max expected accumulated drift.
        // For 200 PPM over 60s: 60 * 200e-6 * 48000 = 576 samples. Use 1000 to be safe.
        let maxSearchSamples = 1000
        let anchorSeconds = min(2.0, windowSeconds / 2.0)
        let anchorSamples = Int(anchorSeconds * sr)

        var windowOffsets: [(time: Double, offset: Double)] = []
        var currentTime = windowSeconds / 2.0

        while currentTime + windowSeconds / 2.0 <= totalDuration {
            let centerSample = Int(currentTime * sr)

            // Reference anchor: anchorSamples around centerSample
            let refStart = max(0, centerSample - anchorSamples / 2)
            let refEnd = min(reference.sampleCount, refStart + anchorSamples)
            guard refEnd > refStart else {
                currentTime += hopSeconds
                continue
            }
            let refSlice = Array(reference.samples[refStart..<refEnd])
            let actualAnchorLen = refSlice.count

            // Compute reference energy for normalization
            var refEnergy: Float = 0
            vDSP_svesq(refSlice, 1, &refEnergy, vDSP_Length(actualAnchorLen))
            guard refEnergy > 1e-10 else {
                currentTime += hopSeconds
                continue
            }

            // Search target over lag range [-maxSearchSamples, +maxSearchSamples]
            var bestLag = 0
            var bestScore: Float = -1

            for lag in -maxSearchSamples...maxSearchSamples {
                let tgtStart = refStart + lag
                let tgtEnd = tgtStart + actualAnchorLen
                guard tgtStart >= 0, tgtEnd <= target.sampleCount else { continue }

                let tgtSlice = Array(target.samples[tgtStart..<tgtEnd])

                var dotProduct: Float = 0
                vDSP_dotpr(refSlice, 1, tgtSlice, 1, &dotProduct, vDSP_Length(actualAnchorLen))

                var tgtEnergy: Float = 0
                vDSP_svesq(tgtSlice, 1, &tgtEnergy, vDSP_Length(actualAnchorLen))

                let denom = sqrt(refEnergy * tgtEnergy)
                guard denom > 1e-15 else { continue }

                let score = dotProduct / denom
                if score > bestScore {
                    bestScore = score
                    bestLag = lag
                }
            }

            if bestScore > 0.5 {
                let offsetSeconds = Double(bestLag) / sr
                windowOffsets.append((time: currentTime, offset: offsetSeconds))
            }

            currentTime += hopSeconds
        }

        guard windowOffsets.count >= 2 else {
            // Fallback: use GCC-PHAT on the full signals
            let correlator = GCCPHATCorrelator()
            let simpleResult = try correlator.findOffset(reference: reference, target: target)
            return DriftResult(baseOffset: simpleResult.offsetSeconds, driftPPM: 0, windowOffsets: [])
        }

        let xs = windowOffsets.map(\.time)
        let ys = windowOffsets.map(\.offset)
        let (driftRate, baseOffset) = Self.linearRegression(xs: xs, ys: ys)

        // driftRate is the slope of (time, targetOffset):
        // negative slope means target leads reference (runs faster = positive PPM).
        return DriftResult(
            baseOffset: baseOffset,
            driftPPM: -driftRate * 1_000_000,
            windowOffsets: windowOffsets
        )
    }

    static func linearRegression(xs: [Double], ys: [Double]) -> (slope: Double, intercept: Double) {
        let n = Double(xs.count)
        let sumX = xs.reduce(0, +)
        let sumY = ys.reduce(0, +)
        let sumXY = zip(xs, ys).reduce(0) { $0 + $1.0 * $1.1 }
        let sumXX = xs.reduce(0) { $0 + $1 * $1 }

        let denominator = n * sumXX - sumX * sumX
        guard abs(denominator) > 1e-15 else {
            return (slope: 0, intercept: sumY / n)
        }

        let slope = (n * sumXY - sumX * sumY) / denominator
        let intercept = (sumY - slope * sumX) / n
        return (slope: slope, intercept: intercept)
    }
}
