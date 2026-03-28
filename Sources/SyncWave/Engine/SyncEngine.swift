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

        for (label, target) in targets {
            // Use GCC-PHAT to find offset
            let result = try correlator.findOffset(reference: reference, target: target)

            // Drift correction only for long recordings (> 5 min)
            var driftPPM: Double = 0
            if reference.duration > 300 && target.duration > 300 {
                let driftResult = try driftCorrector.detectDrift(reference: reference, target: target)
                driftPPM = driftResult.driftPPM
            }

            alignments.append(SyncAlignment(
                label: label,
                offset: result.offsetSeconds,
                driftPPM: driftPPM,
                confidence: result.confidence
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
