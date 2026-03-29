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

            // Phase 2: Fine alignment using plain cross-correlation on bandpass-filtered audio.
            // The envelope gives ~5ms accuracy. We refine to sub-millisecond (~0.02ms at 48kHz)
            // by correlating a narrow window of the preprocessed audio around the coarse offset.
            var finalOffsetSeconds = coarseOffsetSeconds

            if useEnvelope && refProcessed.sampleCount > 0 && tgtProcessed.sampleCount > 0 {
                let searchWindowSeconds = 0.2 // ±200ms search range around coarse offset
                let extractWindowSeconds = 2.0 // 2 seconds of audio for correlation

                // Find a point in the reference that has good content (middle of the clip)
                let refCenterTime = refProcessed.duration / 2.0
                // The corresponding point in the target, accounting for the coarse offset.
                // If target starts +5s later on timeline, an event at ref T=12s is at target T=12-5=7s.
                let tgtCenterTime = refCenterTime - coarseOffsetSeconds

                // Extract 2-second windows from both signals
                let refWindow = refProcessed.window(centerSeconds: refCenterTime, windowSeconds: extractWindowSeconds)
                // Extract a wider window from target to allow for the search range
                let tgtWindow = tgtProcessed.window(
                    centerSeconds: tgtCenterTime,
                    windowSeconds: extractWindowSeconds + searchWindowSeconds * 2
                )

                if refWindow.sampleCount > 1000 && tgtWindow.sampleCount > 1000 {
                    // Plain cross-correlation (not GCC-PHAT — more reliable for fine alignment)
                    let fineResult = plainCrossCorrelation(reference: refWindow, target: tgtWindow)
                    let fineOffsetSeconds = fineResult.offsetSeconds

                    // Accept the fine result only if it's within the search window (plausible)
                    if abs(fineOffsetSeconds) < searchWindowSeconds {
                        finalOffsetSeconds = coarseOffsetSeconds + fineOffsetSeconds
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

    /// Plain (non-PHAT) cross-correlation via FFT for fine sub-millisecond alignment.
    /// More reliable than GCC-PHAT for fine refinement because it preserves amplitude info.
    private func plainCrossCorrelation(reference: AudioBuffer, target: AudioBuffer) -> CorrelationResult {
        let refSamples = reference.samples
        let tgtSamples = target.samples
        let totalLength = refSamples.count + tgtSamples.count
        let log2n = vDSP_Length(ceil(log2(Double(totalLength))))
        let fftSize = Int(1 << log2n)
        let halfSize = fftSize / 2

        guard let fftSetup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2)) else {
            return CorrelationResult(offsetSamples: 0, offsetSeconds: 0, confidence: 0)
        }
        defer { vDSP_destroy_fftsetup(fftSetup) }

        // Forward FFT helper
        func forwardFFT(_ signal: [Float]) -> ([Float], [Float]) {
            var padded = [Float](repeating: 0, count: fftSize)
            padded.replaceSubrange(0..<min(signal.count, fftSize), with: signal.prefix(fftSize))
            var r = [Float](repeating: 0, count: halfSize)
            var im = [Float](repeating: 0, count: halfSize)
            padded.withUnsafeMutableBufferPointer { paddedPtr in
                paddedPtr.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: halfSize) { complexPtr in
                    r.withUnsafeMutableBufferPointer { rPtr in
                        im.withUnsafeMutableBufferPointer { iPtr in
                            var split = DSPSplitComplex(realp: rPtr.baseAddress!, imagp: iPtr.baseAddress!)
                            vDSP_ctoz(complexPtr, 2, &split, 1, vDSP_Length(halfSize))
                            vDSP_fft_zrip(fftSetup, &split, 1, log2n, FFTDirection(kFFTDirection_Forward))
                        }
                    }
                }
            }
            return (r, im)
        }

        let (refR, refI) = forwardFFT(refSamples)
        let (tgtR, tgtI) = forwardFFT(tgtSamples)

        // Cross-power spectrum: tgt * conj(ref) — NO whitening (plain cross-correlation)
        var crossReal = [Float](repeating: 0, count: halfSize)
        var crossImag = [Float](repeating: 0, count: halfSize)
        var tmp = [Float](repeating: 0, count: halfSize)

        vDSP_vmul(tgtR, 1, refR, 1, &crossReal, 1, vDSP_Length(halfSize))
        vDSP_vmul(tgtI, 1, refI, 1, &tmp, 1, vDSP_Length(halfSize))
        vDSP_vadd(crossReal, 1, tmp, 1, &crossReal, 1, vDSP_Length(halfSize))

        vDSP_vmul(tgtI, 1, refR, 1, &crossImag, 1, vDSP_Length(halfSize))
        vDSP_vmul(tgtR, 1, refI, 1, &tmp, 1, vDSP_Length(halfSize))
        vDSP_vsub(tmp, 1, crossImag, 1, &crossImag, 1, vDSP_Length(halfSize))

        // IFFT
        var correlation = [Float](repeating: 0, count: fftSize)
        crossReal.withUnsafeMutableBufferPointer { rPtr in
            crossImag.withUnsafeMutableBufferPointer { iPtr in
                var split = DSPSplitComplex(realp: rPtr.baseAddress!, imagp: iPtr.baseAddress!)
                vDSP_fft_zrip(fftSetup, &split, 1, log2n, FFTDirection(kFFTDirection_Inverse))
                correlation.withUnsafeMutableBufferPointer { corrPtr in
                    corrPtr.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: halfSize) { complexPtr in
                        vDSP_ztoc(&split, 1, complexPtr, 2, vDSP_Length(halfSize))
                    }
                }
            }
        }

        // Scale
        var scale = 1.0 / Float(fftSize)
        vDSP_vsmul(correlation, 1, &scale, &correlation, 1, vDSP_Length(fftSize))

        // Find peak
        var absCorr = [Float](repeating: 0, count: fftSize)
        vDSP_vabs(correlation, 1, &absCorr, 1, vDSP_Length(fftSize))

        var maxVal: Float = 0
        var maxIdx: vDSP_Length = 0
        vDSP_maxvi(absCorr, 1, &maxVal, &maxIdx, vDSP_Length(fftSize))

        var offsetSamples = Int(maxIdx)
        if offsetSamples > fftSize / 2 {
            offsetSamples -= fftSize
        }

        // Normalized confidence
        var refEnergy: Float = 0
        var tgtEnergy: Float = 0
        vDSP_svesq(refSamples, 1, &refEnergy, vDSP_Length(refSamples.count))
        vDSP_svesq(tgtSamples, 1, &tgtEnergy, vDSP_Length(tgtSamples.count))
        let denom = sqrt(Double(refEnergy) * Double(tgtEnergy))
        let confidence = denom > 1e-30 ? Double(maxVal) / denom : 0

        // No negation for fine alignment: we're measuring residual offset within aligned windows.
        // Positive = target content appears later in the window = needs more positive timeline offset.
        return CorrelationResult(
            offsetSamples: Double(offsetSamples),
            offsetSeconds: Double(offsetSamples) / reference.sampleRate,
            confidence: min(1.0, confidence)
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

    /// Progress callback with percentage (0-1) and a status message.
    typealias ProgressCallback = (Double, String) -> Void

    /// Full pipeline: extract audio from files, then sync.
    func syncFiles(
        referenceURL: URL,
        targetURLs: [(label: String, url: URL)],
        progress: ProgressCallback? = nil
    ) async throws -> SyncOutput {
        // Total phases: extract ref (1) + extract each target (N) + sync each target (N * 4 sub-steps)
        let n = Double(targetURLs.count)
        let extractWeight = 0.4  // 40% of time = extraction
        let syncWeight = 0.6     // 60% of time = DSP processing

        // Phase 1: Extract reference audio
        let refName = referenceURL.lastPathComponent
        progress?(0.01, "Extraction audio : \(refName)...")
        let referenceBuffer = try await extractor.extract(from: referenceURL)
        progress?(extractWeight / (n + 1), "Extraction audio : \(refName) ✓")

        // Phase 2: Extract target audio
        var targets: [(label: String, buffer: AudioBuffer)] = []
        for (i, (label, url)) in targetURLs.enumerated() {
            progress?(extractWeight * Double(i + 1) / (n + 1), "Extraction audio : \(label)...")
            let buffer = try await extractor.extract(from: url)
            targets.append((label: label, buffer: buffer))
            progress?(extractWeight * Double(i + 2) / (n + 1), "Extraction audio : \(label) ✓")
        }

        // Phase 3: Preprocessing
        progress?(extractWeight, "Preprocessing : filtrage et normalisation...")
        let refProcessed = referenceBuffer
            .removeDCOffset()
            .bandpassFiltered(lowFreq: 200, highFreq: 4000)
            .normalized()

        var processedTargets: [(label: String, raw: AudioBuffer, processed: AudioBuffer)] = []
        for (label, buffer) in targets {
            let processed = buffer
                .removeDCOffset()
                .bandpassFiltered(lowFreq: 200, highFreq: 4000)
                .normalized()
            processedTargets.append((label: label, raw: buffer, processed: processed))
        }
        progress?(extractWeight + 0.05, "Preprocessing terminé")

        // Phase 4: Sync each target
        let startTime = CFAbsoluteTimeGetCurrent()
        var alignments: [SyncAlignment] = []
        let syncStepWeight = syncWeight / max(1, n)

        for (i, (label, raw, processed)) in processedTargets.enumerated() {
            let baseProgress = extractWeight + 0.05 + syncStepWeight * Double(i)

            // Step 1: Envelope correlation
            progress?(baseProgress + syncStepWeight * 0.1, "Corrélation enveloppe : \(label)...")

            let useEnvelope = referenceBuffer.duration > 3.0 && raw.duration > 3.0
            let coarseOffsetSeconds: TimeInterval
            var confidence: Double

            if useEnvelope {
                let refEnvelope = refProcessed.energyEnvelope(windowSeconds: 0.02, hopSeconds: 0.005)
                let tgtEnvelope = processed.energyEnvelope(windowSeconds: 0.02, hopSeconds: 0.005)

                let refVar = envelopeVariance(refEnvelope.samples)
                let tgtVar = envelopeVariance(tgtEnvelope.samples)
                let envelopeUsable = refVar > 0.4 && tgtVar > 0.4

                if envelopeUsable {
                    let coarseResult = try correlator.findOffset(reference: refEnvelope, target: tgtEnvelope)
                    coarseOffsetSeconds = -coarseResult.offsetSeconds
                    confidence = coarseResult.confidence
                } else {
                    let directResult = try correlator.findOffset(reference: referenceBuffer, target: raw)
                    coarseOffsetSeconds = directResult.offsetSeconds
                    confidence = directResult.confidence
                }
            } else {
                let directResult = try correlator.findOffset(reference: referenceBuffer, target: raw)
                coarseOffsetSeconds = directResult.offsetSeconds
                confidence = directResult.confidence
            }

            progress?(baseProgress + syncStepWeight * 0.5, "Affinage sub-ms : \(label)...")

            // Step 2: Fine alignment
            var finalOffsetSeconds = coarseOffsetSeconds

            if useEnvelope && refProcessed.sampleCount > 0 && processed.sampleCount > 0 {
                let searchWindowSeconds = 0.2
                let extractWindowSeconds = 2.0
                let refCenterTime = refProcessed.duration / 2.0
                let tgtCenterTime = refCenterTime - coarseOffsetSeconds

                let refWindow = refProcessed.window(centerSeconds: refCenterTime, windowSeconds: extractWindowSeconds)
                let tgtWindow = processed.window(
                    centerSeconds: tgtCenterTime,
                    windowSeconds: extractWindowSeconds + searchWindowSeconds * 2
                )

                if refWindow.sampleCount > 1000 && tgtWindow.sampleCount > 1000 {
                    let fineResult = plainCrossCorrelation(reference: refWindow, target: tgtWindow)
                    if abs(fineResult.offsetSeconds) < searchWindowSeconds {
                        finalOffsetSeconds = coarseOffsetSeconds + fineResult.offsetSeconds
                        confidence = max(confidence, fineResult.confidence)
                    }
                }
            }

            progress?(baseProgress + syncStepWeight * 0.8, "Drift : \(label)...")

            // Step 3: Drift correction
            var driftPPM: Double = 0
            if referenceBuffer.duration > 300 && raw.duration > 300 {
                let driftResult = try driftCorrector.detectDrift(reference: refProcessed, target: processed)
                driftPPM = driftResult.driftPPM
            }

            alignments.append(SyncAlignment(
                label: label,
                offset: finalOffsetSeconds,
                driftPPM: driftPPM,
                confidence: confidence
            ))

            progress?(baseProgress + syncStepWeight, "\(label) synchronisé ✓")
        }

        let processingTime = CFAbsoluteTimeGetCurrent() - startTime
        progress?(1.0, "Synchronisation terminée")

        return SyncOutput(alignments: alignments, processingTime: processingTime)
    }
}
