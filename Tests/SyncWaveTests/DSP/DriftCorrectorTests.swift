// Tests/SyncWaveTests/DSP/DriftCorrectorTests.swift
import XCTest
@testable import SyncWave

final class DriftCorrectorTests: XCTestCase {

    func testDetectsKnownDrift() throws {
        let reference = TestSignalGenerator.complexSignal(sampleRate: 48000, duration: 60)
        let drifted = TestSignalGenerator.driftedCopy(of: reference, driftPPM: 50)

        let corrector = DriftCorrector(windowSeconds: 10, overlapRatio: 0.5)
        let result = try corrector.detectDrift(reference: reference, target: drifted)

        XCTAssertEqual(result.driftPPM, 50, accuracy: 10,
                       "Expected ~50 PPM drift, got \(result.driftPPM)")
    }

    func testZeroDriftForIdenticalSignals() throws {
        let signal = TestSignalGenerator.complexSignal(sampleRate: 48000, duration: 30)

        let corrector = DriftCorrector(windowSeconds: 10, overlapRatio: 0.5)
        let result = try corrector.detectDrift(reference: signal, target: signal)

        XCTAssertEqual(result.driftPPM, 0, accuracy: 5,
                       "Identical signals should have ~0 PPM drift")
    }

    func testLinearRegressionWithKnownPoints() {
        let xs: [Double] = [0, 1, 2, 3, 4, 5]
        let ys: [Double] = [3, 5, 7, 9, 11, 13]
        let (slope, intercept) = DriftCorrector.linearRegression(xs: xs, ys: ys)

        XCTAssertEqual(slope, 2.0, accuracy: 0.001)
        XCTAssertEqual(intercept, 3.0, accuracy: 0.001)
    }
}
