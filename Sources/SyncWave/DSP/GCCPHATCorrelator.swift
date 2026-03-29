import Foundation
import Accelerate

/// Result of a GCC-PHAT cross-correlation.
struct CorrelationResult {
    /// Positive = target starts later (is delayed relative to reference).
    /// Negative = target starts earlier (leads the reference).
    let offsetSamples: Double
    let offsetSeconds: TimeInterval
    /// Normalized cross-correlation coefficient at the detected lag, in [0, 1].
    let confidence: Double
}

/// GCC-PHAT (Generalized Cross-Correlation with Phase Transform) time-delay estimator.
///
/// Finds the sample-accurate time offset between two recordings of the same audio scene.
/// Uses Apple's Accelerate/vDSP for high-performance FFT computation.
struct GCCPHATCorrelator {

    enum CorrelatorError: Error {
        case emptySignal
        case fftSetupFailed
    }

    func findOffset(reference: AudioBuffer, target: AudioBuffer) throws -> CorrelationResult {
        guard !reference.samples.isEmpty, !target.samples.isEmpty else {
            throw CorrelatorError.emptySignal
        }

        let refSamples = reference.samples
        let tgtSamples = target.samples

        print("[DEBUG GCCPHATCorrelator] findOffset using GCC-PHAT: refSamples=\(refSamples.count) tgtSamples=\(tgtSamples.count) refRate=\(reference.sampleRate)")

        // --- Step 1: GCC-PHAT to find the lag ---
        let (lag, peakConfidence) = gccphatLagWithConfidence(ref: refSamples, tgt: tgtSamples)

        // --- Step 2: Use peak-to-mean ratio as primary confidence ---
        // NCC is too strict for signals from different microphones.
        // Peak-to-mean ratio detects a clear peak regardless of waveform similarity.
        let ncc = abs(normalizedCrossCorr(ref: refSamples, tgt: tgtSamples, lag: lag))
        // Use the higher of the two confidence measures
        let confidence = max(ncc, peakConfidence)

        print("[DEBUG GCCPHATCorrelator] lag=\(lag) offsetSeconds=\(String(format: "%.6f", Double(lag) / reference.sampleRate)) peakConfidence(peak-to-mean)=\(String(format: "%.6f", peakConfidence)) ncc=\(String(format: "%.6f", ncc)) finalConfidence=\(String(format: "%.6f", confidence))")

        let offsetSamples = Double(lag)
        return CorrelationResult(
            offsetSamples: offsetSamples,
            offsetSeconds: offsetSamples / reference.sampleRate,
            confidence: confidence
        )
    }

    // MARK: - Private helpers

    /// Compute GCC-PHAT correlation and return the lag in samples plus peak-to-mean confidence.
    /// Convention: positive lag means target is delayed relative to reference.
    private func gccphatLagWithConfidence(ref: [Float], tgt: [Float]) -> (lag: Int, confidence: Double) {
        let (lag, _) = gccphatLagInternal(ref: ref, tgt: tgt)
        return (lag, gccphatPeakConfidence(ref: ref, tgt: tgt))
    }

    /// Compute peak-to-mean ratio from GCC-PHAT correlation as confidence.
    /// A clear, sharp peak (even if small) gives high confidence.
    private func gccphatPeakConfidence(ref: [Float], tgt: [Float]) -> Double {
        let totalLength = ref.count + tgt.count
        let log2n = vDSP_Length(ceil(log2(Double(totalLength))))
        let fftSize = Int(1 << log2n)

        guard let fftSetup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2)) else { return 0 }
        defer { vDSP_destroy_fftsetup(fftSetup) }

        let halfSize = fftSize / 2
        let (refR, refI) = fftForward(ref, fftSetup: fftSetup, log2n: log2n, fftSize: fftSize, halfSize: halfSize)
        let (tgtR, tgtI) = fftForward(tgt, fftSetup: fftSetup, log2n: log2n, fftSize: fftSize, halfSize: halfSize)

        var crossReal = [Float](repeating: 0, count: halfSize)
        var crossImag = [Float](repeating: 0, count: halfSize)
        var tmp = [Float](repeating: 0, count: halfSize)

        vDSP_vmul(tgtR, 1, refR, 1, &crossReal, 1, vDSP_Length(halfSize))
        vDSP_vmul(tgtI, 1, refI, 1, &tmp, 1, vDSP_Length(halfSize))
        vDSP_vadd(crossReal, 1, tmp, 1, &crossReal, 1, vDSP_Length(halfSize))

        vDSP_vmul(tgtI, 1, refR, 1, &crossImag, 1, vDSP_Length(halfSize))
        vDSP_vmul(tgtR, 1, refI, 1, &tmp, 1, vDSP_Length(halfSize))
        vDSP_vsub(tmp, 1, crossImag, 1, &crossImag, 1, vDSP_Length(halfSize))

        // No PHAT whitening — use raw cross-power spectrum for peak detection
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

        var absCorr = [Float](repeating: 0, count: fftSize)
        vDSP_vabs(correlation, 1, &absCorr, 1, vDSP_Length(fftSize))

        var maxVal: Float = 0
        var maxIdx: vDSP_Length = 0
        vDSP_maxvi(absCorr, 1, &maxVal, &maxIdx, vDSP_Length(fftSize))

        var meanVal: Float = 0
        vDSP_meanv(absCorr, 1, &meanVal, vDSP_Length(fftSize))

        // Peak-to-mean ratio, normalized to 0-1 range
        // A ratio > 5 means a very clear peak. We map 1→0, 10→1.
        guard meanVal > 0 else { return 0 }
        let ratio = Double(maxVal / meanVal)
        let confidence = min(1.0, max(0, (ratio - 1.0) / 9.0))
        return confidence
    }

    /// Helper: compute forward FFT
    private func fftForward(_ signal: [Float], fftSetup: FFTSetup, log2n: vDSP_Length, fftSize: Int, halfSize: Int) -> ([Float], [Float]) {
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

    private func gccphatLag(ref: [Float], tgt: [Float]) -> Int {
        return gccphatLagInternal(ref: ref, tgt: tgt).lag
    }

    private func gccphatLagInternal(ref: [Float], tgt: [Float]) -> (lag: Int, absCorr: [Float]) {
        let totalLength = ref.count + tgt.count
        let log2n = vDSP_Length(ceil(log2(Double(totalLength))))
        let fftSize = Int(1 << log2n)
        let halfSize = fftSize / 2

        guard let fftSetup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2)) else {
            return (lag: 0, absCorr: [])
        }
        defer { vDSP_destroy_fftsetup(fftSetup) }

        // Compute forward FFT of a zero-padded real signal
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

        let (refR, refI) = forwardFFT(ref)
        let (tgtR, tgtI) = forwardFFT(tgt)

        // Cross-power spectrum: R[k] = FFT(tgt)[k] * conj(FFT(ref)[k])
        // Convention tgt * conj(ref): positive lag = tgt is delayed.
        // R.real = tgtReal * refReal + tgtImag * refImag  (re(a) * re(b) + im(a) * im(b))
        // R.imag = tgtImag * refReal - tgtReal * refImag  (im(a) * re(b) - re(a) * im(b))
        var crossReal = [Float](repeating: 0, count: halfSize)
        var crossImag = [Float](repeating: 0, count: halfSize)
        var tmp = [Float](repeating: 0, count: halfSize)

        vDSP_vmul(tgtR, 1, refR, 1, &crossReal, 1, vDSP_Length(halfSize))
        vDSP_vmul(tgtI, 1, refI, 1, &tmp, 1, vDSP_Length(halfSize))
        vDSP_vadd(crossReal, 1, tmp, 1, &crossReal, 1, vDSP_Length(halfSize))

        vDSP_vmul(tgtI, 1, refR, 1, &crossImag, 1, vDSP_Length(halfSize))
        vDSP_vmul(tgtR, 1, refI, 1, &tmp, 1, vDSP_Length(halfSize))
        // vDSP_vsub(A, B, C): C = B - A
        vDSP_vsub(tmp, 1, crossImag, 1, &crossImag, 1, vDSP_Length(halfSize))

        // PHAT whitening: normalize each bin by its magnitude to suppress amplitude
        var magnitude = [Float](repeating: 0, count: halfSize)
        crossReal.withUnsafeMutableBufferPointer { rPtr in
            crossImag.withUnsafeMutableBufferPointer { iPtr in
                magnitude.withUnsafeMutableBufferPointer { mPtr in
                    var split = DSPSplitComplex(realp: rPtr.baseAddress!, imagp: iPtr.baseAddress!)
                    vDSP_zvabs(&split, 1, mPtr.baseAddress!, 1, vDSP_Length(halfSize))
                }
            }
        }
        let epsilon: Float = 1e-10
        let epsilonVec = [Float](repeating: epsilon, count: halfSize)
        vDSP_vmax(magnitude, 1, epsilonVec, 1, &magnitude, 1, vDSP_Length(halfSize))
        vDSP_vdiv(magnitude, 1, crossReal, 1, &crossReal, 1, vDSP_Length(halfSize))
        vDSP_vdiv(magnitude, 1, crossImag, 1, &crossImag, 1, vDSP_Length(halfSize))

        // Inverse FFT to obtain time-domain GCC-PHAT correlation
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

        // Absolute value for peak detection
        var absCorr = [Float](repeating: 0, count: fftSize)
        vDSP_vabs(correlation, 1, &absCorr, 1, vDSP_Length(fftSize))

        // Find the global peak
        var maxVal: Float = 0
        var maxIdx: vDSP_Length = 0
        vDSP_maxvi(absCorr, 1, &maxVal, &maxIdx, vDSP_Length(fftSize))
        var detectedLag = circularIndexToLag(Int(maxIdx), fftSize: fftSize)

        // Validate the detected lag using normalized cross-correlation.
        // GCC-PHAT can produce a false peak at lag=0 for periodic signals. When the detected
        // lag is 0, check if a better (higher NCC) non-zero candidate exists in the top peaks.
        if detectedLag == 0 {
            let zeroNCC = abs(normalizedCrossCorr(ref: ref, tgt: tgt, lag: 0))
            let halfRefLen = ref.count / 2
            // Collect the top-50 non-zero peaks by GCC-PHAT score within valid range.
            var topPeaks: [(lag: Int, score: Float)] = []
            for i in 1..<fftSize {
                let candidateLag = circularIndexToLag(i, fftSize: fftSize)
                if candidateLag != 0 && abs(candidateLag) < halfRefLen {
                    let score = absCorr[i]
                    if topPeaks.count < 50 {
                        topPeaks.append((lag: candidateLag, score: score))
                        topPeaks.sort { $0.score > $1.score }
                    } else if score > topPeaks.last!.score {
                        topPeaks[49] = (lag: candidateLag, score: score)
                        topPeaks.sort { $0.score > $1.score }
                    }
                }
            }
            // Pick the candidate with highest NCC, if it beats lag=0.
            var bestAltLag = 0
            var bestNCC = zeroNCC
            for peak in topPeaks {
                let ncc = abs(normalizedCrossCorr(ref: ref, tgt: tgt, lag: peak.lag))
                if ncc > bestNCC {
                    bestNCC = ncc
                    bestAltLag = peak.lag
                }
            }
            if bestAltLag != 0 {
                detectedLag = bestAltLag
            }
        }

        return (lag: detectedLag, absCorr: absCorr)
    }

    /// Convert a circular FFT index to a signed lag.
    @inline(__always)
    private func circularIndexToLag(_ index: Int, fftSize: Int) -> Int {
        index > fftSize / 2 ? index - fftSize : index
    }

    /// Compute normalized cross-correlation coefficient at a specific lag.
    /// Returns a value in [-1, 1] where 1 = perfect correlation.
    private func normalizedCrossCorr(ref: [Float], tgt: [Float], lag: Int) -> Double {
        let n = min(ref.count, tgt.count)
        let refStart = max(0, -lag)
        let tgtStart = max(0, lag)
        let overlapLen = n - abs(lag)
        guard overlapLen > 10 else { return 0.0 }  // need at least 10 samples

        let refSlice = Array(ref[refStart..<(refStart + overlapLen)])
        let tgtSlice = Array(tgt[tgtStart..<(tgtStart + overlapLen)])

        var dotProduct: Float = 0
        vDSP_dotpr(refSlice, 1, tgtSlice, 1, &dotProduct, vDSP_Length(overlapLen))

        var refEnergy: Float = 0
        vDSP_svesq(refSlice, 1, &refEnergy, vDSP_Length(overlapLen))

        var tgtEnergy: Float = 0
        vDSP_svesq(tgtSlice, 1, &tgtEnergy, vDSP_Length(overlapLen))

        let denom = sqrt(Double(refEnergy) * Double(tgtEnergy))
        guard denom > 1e-30 else { return 0.0 }
        return Double(dotProduct) / denom
    }
}
