// Sources/SyncWave/DSP/AudioExtractor.swift
import Foundation
import AVFoundation

struct AudioExtractor {

    enum ExtractionError: Error, LocalizedError {
        case noAudioTrack(url: URL)
        case readerSetupFailed(url: URL, underlying: Error)
        case ffmpegFailed(url: URL, exitCode: Int32)
        case ffmpegNotFound
        case noSamplesExtracted(url: URL)

        var errorDescription: String? {
            switch self {
            case .noAudioTrack(let url): return "Pas de piste audio dans \(url.lastPathComponent)"
            case .readerSetupFailed(let url, let err): return "Erreur lecture \(url.lastPathComponent): \(err.localizedDescription)"
            case .ffmpegFailed(let url, let code): return "FFmpeg a échoué sur \(url.lastPathComponent) (code \(code))"
            case .ffmpegNotFound: return "FFmpeg non trouvé. Installer via: brew install ffmpeg"
            case .noSamplesExtracted(let url): return "Aucun échantillon extrait de \(url.lastPathComponent)"
            }
        }
    }

    func extract(from url: URL, targetSampleRate: Double = 48000) async throws -> AudioBuffer {
        do {
            return try await extractWithAVFoundation(from: url, targetSampleRate: targetSampleRate)
        } catch {
            return try await extractWithFFmpeg(from: url, targetSampleRate: targetSampleRate)
        }
    }

    private func extractWithAVFoundation(from url: URL, targetSampleRate: Double) async throws -> AudioBuffer {
        let asset = AVAsset(url: url)
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        guard let audioTrack = audioTracks.first else { throw ExtractionError.noAudioTrack(url: url) }

        let outputSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsNonInterleaved: false,
            AVSampleRateKey: targetSampleRate,
            AVNumberOfChannelsKey: 1
        ]

        let reader: AVAssetReader
        do { reader = try AVAssetReader(asset: asset) }
        catch { throw ExtractionError.readerSetupFailed(url: url, underlying: error) }

        let output = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: outputSettings)
        reader.add(output)
        reader.startReading()

        var allSamples: [Float] = []
        while let sampleBuffer = output.copyNextSampleBuffer() {
            guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { continue }
            let length = CMBlockBufferGetDataLength(blockBuffer)
            var data = Data(count: length)
            data.withUnsafeMutableBytes { ptr in
                CMBlockBufferCopyDataBytes(blockBuffer, atOffset: 0, dataLength: length, destination: ptr.baseAddress!)
            }
            let floatCount = length / MemoryLayout<Float>.size
            let floats = data.withUnsafeBytes { ptr in
                Array(ptr.bindMemory(to: Float.self).prefix(floatCount))
            }
            allSamples.append(contentsOf: floats)
        }

        guard !allSamples.isEmpty else { throw ExtractionError.noSamplesExtracted(url: url) }
        return AudioBuffer(samples: allSamples, sampleRate: targetSampleRate, channelCount: 1)
    }

    private func extractWithFFmpeg(from url: URL, targetSampleRate: Double) async throws -> AudioBuffer {
        guard let path = findFFmpeg() else { throw ExtractionError.ffmpegNotFound }

        let tempOutput = FileManager.default.temporaryDirectory.appendingPathComponent("syncwave_\(UUID().uuidString).raw")
        defer { try? FileManager.default.removeItem(at: tempOutput) }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = ["-i", url.path, "-vn", "-ac", "1", "-ar", String(Int(targetSampleRate)), "-f", "f32le", "-y", tempOutput.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else { throw ExtractionError.ffmpegFailed(url: url, exitCode: process.terminationStatus) }

        let data = try Data(contentsOf: tempOutput)
        let floatCount = data.count / MemoryLayout<Float>.size
        let samples = data.withUnsafeBytes { ptr in Array(ptr.bindMemory(to: Float.self).prefix(floatCount)) }
        guard !samples.isEmpty else { throw ExtractionError.noSamplesExtracted(url: url) }
        return AudioBuffer(samples: samples, sampleRate: targetSampleRate, channelCount: 1)
    }

    private func findFFmpeg() -> String? {
        ["/opt/homebrew/bin/ffmpeg", "/usr/local/bin/ffmpeg", "/usr/bin/ffmpeg"]
            .first { FileManager.default.fileExists(atPath: $0) }
    }
}
