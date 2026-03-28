// Tests/SyncWaveTests/Engine/SyncEngineTests.swift
import XCTest
@testable import SyncWave

final class SyncEngineTests: XCTestCase {

    func testSyncWithKnownOffset() async throws {
        let reference = TestSignalGenerator.complexSignal(sampleRate: 48000, duration: 10)
        let delayed = TestSignalGenerator.delayedCopy(of: reference, offsetSamples: 4800)

        let engine = SyncEngine()
        let result = try engine.syncBuffers(
            reference: reference,
            targets: [("Camera_B", delayed)]
        )

        XCTAssertEqual(result.alignments.count, 1)
        let alignment = result.alignments[0]
        XCTAssertEqual(alignment.offset, 0.1, accuracy: 0.001)
        XCTAssertGreaterThan(alignment.confidence, 0.5)
    }

    func testSyncMultipleTargets() async throws {
        let reference = TestSignalGenerator.complexSignal(sampleRate: 48000, duration: 10)
        let target1 = TestSignalGenerator.delayedCopy(of: reference, offsetSamples: 2400)
        let target2 = TestSignalGenerator.delayedCopy(of: reference, offsetSamples: -1200)

        let engine = SyncEngine()
        let result = try engine.syncBuffers(
            reference: reference,
            targets: [("Camera_B", target1), ("Audio_H6", target2)]
        )

        XCTAssertEqual(result.alignments.count, 2)
        XCTAssertEqual(result.alignments[0].offset, 0.05, accuracy: 0.001)
        XCTAssertEqual(result.alignments[1].offset, -0.025, accuracy: 0.001)
    }
}
