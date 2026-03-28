import XCTest
@testable import SyncWave

final class GCCPHATCorrelatorTests: XCTestCase {

    func testDetectsKnownOffset() throws {
        let reference = TestSignalGenerator.complexSignal(sampleRate: 48000, duration: 10)
        let delayed = TestSignalGenerator.delayedCopy(of: reference, offsetSamples: 4800)

        let correlator = GCCPHATCorrelator()
        let result = try correlator.findOffset(reference: reference, target: delayed)

        XCTAssertEqual(result.offsetSamples, 4800, accuracy: 2,
                       "Expected offset of 4800 samples, got \(result.offsetSamples)")
        XCTAssertGreaterThan(result.confidence, 0.5)
    }

    func testDetectsZeroOffset() throws {
        let signal = TestSignalGenerator.complexSignal(sampleRate: 48000, duration: 5)
        let correlator = GCCPHATCorrelator()
        let result = try correlator.findOffset(reference: signal, target: signal)

        XCTAssertEqual(result.offsetSamples, 0, accuracy: 1)
        XCTAssertGreaterThan(result.confidence, 0.7)
    }

    func testDetectsNegativeOffset() throws {
        let reference = TestSignalGenerator.complexSignal(sampleRate: 48000, duration: 10)
        let early = TestSignalGenerator.delayedCopy(of: reference, offsetSamples: -2400)

        let correlator = GCCPHATCorrelator()
        let result = try correlator.findOffset(reference: reference, target: early)

        XCTAssertEqual(result.offsetSamples, -2400, accuracy: 2)
    }

    func testLowConfidenceForUncorrelatedSignals() throws {
        let signal1 = TestSignalGenerator.sineWave(frequency: 440, sampleRate: 48000, duration: 5)
        let signal2 = TestSignalGenerator.sineWave(frequency: 1000, sampleRate: 48000, duration: 5)

        let correlator = GCCPHATCorrelator()
        let result = try correlator.findOffset(reference: signal1, target: signal2)

        XCTAssertLessThan(result.confidence, 0.5)
    }
}
