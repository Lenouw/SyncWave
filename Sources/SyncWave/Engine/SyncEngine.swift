// Sources/SyncWave/Engine/SyncEngine.swift
import Foundation

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

            let signalLongEnough = reference.duration > 2 * windowDuration
                && target.duration > 2 * windowDuration

            let coarseOffsetSeconds: TimeInterval
            var confidence: Double

            if signalLongEnough {
                // Phase 1 (long signals): Coarse alignment via energy envelope correlation.
                // Envelope compression makes GCC-PHAT tractable over hours of audio.
                let refEnvelope = refProcessed.energyEnvelope(windowSeconds: 0.02, hopSeconds: 0.005)
                let tgtEnvelope = tgtProcessed.energyEnvelope(windowSeconds: 0.02, hopSeconds: 0.005)
                let coarseResult = try correlator.findOffset(reference: refEnvelope, target: tgtEnvelope)
                coarseOffsetSeconds = coarseResult.offsetSeconds
                confidence = coarseResult.confidence
            } else {
                // Short signals: run GCC-PHAT directly on the raw signals.
                // Preprocessing (bandpass, normalization) is designed for real-world camera audio;
                // on short/synthetic signals it can introduce artifacts that mislead GCC-PHAT.
                let directResult = try correlator.findOffset(reference: reference, target: target)
                coarseOffsetSeconds = directResult.offsetSeconds
                confidence = directResult.confidence
            }

            var finalOffsetSeconds = coarseOffsetSeconds

            if signalLongEnough {
                // Phase 2: Fine alignment using GCC-PHAT on a 10-second window centered at
                // the coarse-estimated alignment point in both signals.
                let refCenter = refProcessed.duration / 2.0
                // offset convention: positive = target delayed, negative = target leads.
                // The audio event at reference time T appears in target at time T + offset.
                let tgtCenter = refCenter + coarseOffsetSeconds

                let refWindow = refProcessed.window(centerSeconds: refCenter, windowSeconds: windowDuration)
                let tgtWindow = tgtProcessed.window(
                    centerSeconds: max(windowDuration / 2, min(tgtProcessed.duration - windowDuration / 2, tgtCenter)),
                    windowSeconds: windowDuration
                )

                if refWindow.sampleCount > 0 && tgtWindow.sampleCount > 0 {
                    let fineResult = try correlator.findOffset(reference: refWindow, target: tgtWindow)
                    // Accept the fine result only when it is confident and plausible (within half
                    // the window duration of the coarse estimate).
                    let residual = fineResult.offsetSeconds - coarseOffsetSeconds
                    if fineResult.confidence > 0.1 && abs(residual) <= windowDuration / 2 {
                        finalOffsetSeconds = fineResult.offsetSeconds
                        confidence = max(confidence, fineResult.confidence)
                    }
                }
            }

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
