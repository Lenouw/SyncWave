// Sources/SyncWave/Engine/SyncEngine.swift
import Foundation
import Accelerate

struct SyncAlignment {
    let label: String
    let offset: TimeInterval
    let driftPPM: Double
    let confidence: Double
}

struct SyncOutput {
    let alignments: [SyncAlignment]
    let processingTime: TimeInterval
}

final class SyncEngine {
    private let correlator = GCCPHATCorrelator()
    private let driftCorrector = DriftCorrector()
    private let extractor = AudioExtractor()

    /// Sync audio buffers directly (for testing).
    func syncBuffers(
        reference: AudioBuffer,
        targets: [(label: String, buffer: AudioBuffer)]
    ) throws -> SyncOutput {
        let startTime = CFAbsoluteTimeGetCurrent()
        var alignments: [SyncAlignment] = []

        let windowDuration: TimeInterval = 10.0

        // Full preprocessing: DC removal → bandpass → normalize — used for long recordings.
        let refProcessed = reference
            .removeDCOffset()
            .bandpassFiltered(lowFreq: 200, highFreq: 4000)
            .normalized()

        for (label, target) in targets {
            let tgtProcessed = target
                .removeDCOffset()
                .bandpassFiltered(lowFreq: 200, highFreq: 4000)
                .normalized()

            let useEnvelope = reference.duration > 3.0 && target.duration > 3.0

            let coarseOffsetSeconds: TimeInterval
            var confidence: Double

            if useEnvelope {
                // Primary method: energy envelope cross-correlation on preprocessed signals.
                // Works reliably with real-world camera audio (different mics, gain, noise).
                let refEnvelope = refProcessed.energyEnvelope(windowSeconds: 0.02, hopSeconds: 0.005)
                let tgtEnvelope = tgtProcessed.energyEnvelope(windowSeconds: 0.02, hopSeconds: 0.005)

                // Check if envelopes have enough variation to be useful.
                // Flat envelopes (constant energy, e.g. synthetic signals) can't be correlated.
                let refVar = envelopeVariance(refEnvelope.samples)
                let tgtVar = envelopeVariance(tgtEnvelope.samples)
                // Real audio has coefficient of variation > 0.5 (speech, transients).
                // Synthetic beat patterns from mixed sines have CV ~ 0.1-0.3.
                let envelopeUsable = refVar > 0.4 && tgtVar > 0.4

                if envelopeUsable {
                    let coarseResult = try correlator.findOffset(reference: refEnvelope, target: tgtEnvelope)
                    // Negate: envelope correlation returns the lag to align envelopes,
                    // but we need the timeline offset (how much later the target starts).
                    // The cross-correlation convention for envelopes is inverted vs raw audio.
                    coarseOffsetSeconds = -coarseResult.offsetSeconds
                    confidence = coarseResult.confidence
                } else {
                    // Flat envelope (constant energy, e.g. synthetic test signals)
                    // Fall back to GCC-PHAT on raw signals (preprocessing can distort synthetic signals)
                    let directResult = try correlator.findOffset(reference: reference, target: target)
                    coarseOffsetSeconds = directResult.offsetSeconds
                    confidence = directResult.confidence
                }
            } else {
                // Very short signals (< 3s): direct GCC-PHAT on raw signals.
                let directResult = try correlator.findOffset(reference: reference, target: target)
                coarseOffsetSeconds = directResult.offsetSeconds
                confidence = directResult.confidence
            }

            var finalOffsetSeconds = coarseOffsetSeconds

            // Drift correction only for long recordings (> 5 min)
            var driftPPM: Double = 0
            if reference.duration > 300 && target.duration > 300 {
                let driftResult = try driftCorrector.detectDrift(reference: refProcessed, target: tgtProcessed)
                driftPPM = driftResult.driftPPM
            }

            alignments.append(SyncAlignment(
                label: label,
                offset: finalOffsetSeconds,
                driftPPM: driftPPM,
                confidence: confidence
            ))
        }

        return SyncOutput(
            alignments: alignments,
            processingTime: CFAbsoluteTimeGetCurrent() - startTime
        )
    }

    /// Coefficient of variation of an envelope. Low = flat signal, high = dynamic signal.
    private func envelopeVariance(_ samples: [Float]) -> Double {
        guard samples.count > 1 else { return 0 }
        var mean: Float = 0
        vDSP_meanv(samples, 1, &mean, vDSP_Length(samples.count))
        guard mean > 1e-10 else { return 0 }
        var sumSqDiff: Float = 0
        for s in samples {
            let diff = s - mean
            sumSqDiff += diff * diff
        }
        let stddev = sqrt(sumSqDiff / Float(samples.count))
        return Double(stddev / mean) // coefficient of variation
    }

    /// Full pipeline: extract audio from files, then sync.
    func syncFiles(
        referenceURL: URL,
        targetURLs: [(label: String, url: URL)],
        progress: ((Double) -> Void)? = nil
    ) async throws -> SyncOutput {
        let totalSteps = Double(targetURLs.count + 1)
        var currentStep = 0.0

        let referenceBuffer = try await extractor.extract(from: referenceURL)
        currentStep += 1
        progress?(currentStep / totalSteps)

        var targets: [(label: String, buffer: AudioBuffer)] = []
        for (label, url) in targetURLs {
            let buffer = try await extractor.extract(from: url)
            targets.append((label: label, buffer: buffer))
            currentStep += 1
            progress?(currentStep / totalSteps)
        }

        return try syncBuffers(reference: referenceBuffer, targets: targets)
    }
}
