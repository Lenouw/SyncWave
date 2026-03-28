// Tests/SyncWaveTests/DSP/AudioExtractorTests.swift
import XCTest
@testable import SyncWave

final class AudioExtractorTests: XCTestCase {

    func testExtractsAudioFromWAV() async throws {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("test_\(UUID().uuidString).wav")
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let sampleRate: Int = 44100
        let numSamples = sampleRate
        try writeTestWAV(to: tempURL, sampleRate: sampleRate, numSamples: numSamples)

        let extractor = AudioExtractor()
        let buffer = try await extractor.extract(from: tempURL, targetSampleRate: 48000)

        XCTAssertGreaterThan(buffer.sampleCount, 0)
        XCTAssertEqual(buffer.sampleRate, 48000)
        XCTAssertEqual(buffer.channelCount, 1)
        XCTAssertEqual(buffer.duration, 1.0, accuracy: 0.1)
    }

    private func writeTestWAV(to url: URL, sampleRate: Int, numSamples: Int) throws {
        var data = Data()
        let bitsPerSample: Int = 16
        let numChannels: Int = 1
        let byteRate = sampleRate * numChannels * (bitsPerSample / 8)
        let blockAlign = numChannels * (bitsPerSample / 8)
        let dataSize = numSamples * blockAlign

        data.append(contentsOf: "RIFF".utf8)
        data.append(contentsOf: withUnsafeBytes(of: UInt32(36 + dataSize).littleEndian) { Array($0) })
        data.append(contentsOf: "WAVE".utf8)
        data.append(contentsOf: "fmt ".utf8)
        data.append(contentsOf: withUnsafeBytes(of: UInt32(16).littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: UInt16(1).littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: UInt16(numChannels).littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: UInt32(sampleRate).littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: UInt32(byteRate).littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: UInt16(blockAlign).littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: UInt16(bitsPerSample).littleEndian) { Array($0) })
        data.append(contentsOf: "data".utf8)
        data.append(contentsOf: withUnsafeBytes(of: UInt32(dataSize).littleEndian) { Array($0) })
        for i in 0..<numSamples {
            let t = Double(i) / Double(sampleRate)
            let sample = Int16(sin(2.0 * .pi * 440.0 * t) * 16000)
            data.append(contentsOf: withUnsafeBytes(of: sample.littleEndian) { Array($0) })
        }
        try data.write(to: url)
    }
}
