import Foundation
import AVFoundation
import Accelerate

/// Generates downsampled waveform peak data from audio files and video containers.
/// Each channel produces an array of Float values representing amplitude peaks.
actor WaveformGenerator {
    static let defaultSamplesPerChannel = 200

    /// Generate waveform peak data for all channels.
    /// Works with both pure audio files (WAV, AIFF) and video containers (MP4, MOV).
    func generateWaveform(url: URL, samplesCount: Int = defaultSamplesPerChannel) async throws -> [[Float]] {
        // Try AVAudioFile first (works for WAV, AIFF, MP3, etc.)
        if let result = try? generateFromAudioFile(url: url, samplesCount: samplesCount), !result.isEmpty {
            return result
        }
        // Fallback to AVAssetReader for video containers (MP4, MOV, MXF, etc.)
        return try await generateFromAsset(url: url, samplesCount: samplesCount)
    }

    /// Read waveform from pure audio files via AVAudioFile
    private func generateFromAudioFile(url: URL, samplesCount: Int) throws -> [[Float]] {
        let file = try AVAudioFile(forReading: url)
        let format = file.processingFormat
        let channelCount = Int(format.channelCount)
        let totalFrames = AVAudioFrameCount(file.length)

        guard totalFrames > 0, channelCount > 0 else { return [] }

        let framesPerSample = Int(totalFrames) / samplesCount
        guard framesPerSample > 0 else {
            return Array(repeating: [Float](repeating: 0, count: samplesCount), count: channelCount)
        }

        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: totalFrames) else { return [] }
        try file.read(into: buffer)

        return extractPeaks(buffer: buffer, channelCount: channelCount, totalFrames: Int(totalFrames), samplesCount: samplesCount)
    }

    /// Read waveform from video containers via AVAssetReader
    private func generateFromAsset(url: URL, samplesCount: Int) async throws -> [[Float]] {
        let asset = AVAsset(url: url)
        guard let audioTrack = try? await asset.loadTracks(withMediaType: .audio).first else { return [] }

        let outputSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false
        ]

        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: outputSettings)
        reader.add(output)
        reader.startReading()

        // Read all sample buffers into a contiguous Float array
        var allSamples = [Float]()
        var channelCount = 2  // default stereo

        while let sampleBuffer = output.copyNextSampleBuffer() {
            guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { continue }

            // Get channel count from format description
            if let formatDesc = CMSampleBufferGetFormatDescription(sampleBuffer) {
                let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(formatDesc)
                if let ch = asbd?.pointee.mChannelsPerFrame, ch > 0 {
                    channelCount = Int(ch)
                }
            }

            let length = CMBlockBufferGetDataLength(blockBuffer)
            let floatCount = length / MemoryLayout<Float>.size
            var data = [Float](repeating: 0, count: floatCount)
            CMBlockBufferCopyDataBytes(blockBuffer, atOffset: 0, dataLength: length, destination: &data)
            allSamples.append(contentsOf: data)
        }

        guard !allSamples.isEmpty, channelCount > 0 else { return [] }

        // Interleaved data: deinterleave into per-channel arrays
        let totalFrames = allSamples.count / channelCount
        guard totalFrames > 0 else { return [] }

        let framesPerSample = totalFrames / samplesCount
        guard framesPerSample > 0 else {
            return Array(repeating: [Float](repeating: 0, count: samplesCount), count: channelCount)
        }

        var result = [[Float]](repeating: [], count: channelCount)

        for ch in 0..<channelCount {
            var peaks = [Float]()
            peaks.reserveCapacity(samplesCount)

            for i in 0..<samplesCount {
                let startFrame = i * framesPerSample
                let endFrame = min(startFrame + framesPerSample, totalFrames)
                var maxVal: Float = 0
                for f in startFrame..<endFrame {
                    let val = abs(allSamples[f * channelCount + ch])
                    if val > maxVal { maxVal = val }
                }
                peaks.append(maxVal)
            }

            // Normalize to [0, 1]
            var globalMax: Float = 0
            vDSP_maxv(peaks, 1, &globalMax, vDSP_Length(peaks.count))
            if globalMax > 0 {
                var scale = 1.0 / globalMax
                vDSP_vsmul(peaks, 1, &scale, &peaks, 1, vDSP_Length(peaks.count))
            }

            result[ch] = peaks
        }

        return result
    }

    /// Extract peaks from a non-interleaved PCM buffer (AVAudioFile output)
    private func extractPeaks(buffer: AVAudioPCMBuffer, channelCount: Int, totalFrames: Int, samplesCount: Int) -> [[Float]] {
        let framesPerSample = totalFrames / samplesCount
        var result = [[Float]](repeating: [], count: channelCount)

        for ch in 0..<channelCount {
            guard let channelData = buffer.floatChannelData?[ch] else { continue }
            var peaks = [Float]()
            peaks.reserveCapacity(samplesCount)

            for i in 0..<samplesCount {
                let start = i * framesPerSample
                let end = min(start + framesPerSample, totalFrames)
                let count = end - start
                guard count > 0 else {
                    peaks.append(0)
                    continue
                }
                var maxVal: Float = 0
                vDSP_maxmgv(channelData + start, 1, &maxVal, vDSP_Length(count))
                peaks.append(maxVal)
            }

            var globalMax: Float = 0
            vDSP_maxv(peaks, 1, &globalMax, vDSP_Length(peaks.count))
            if globalMax > 0 {
                var scale = 1.0 / globalMax
                vDSP_vsmul(peaks, 1, &scale, &peaks, 1, vDSP_Length(peaks.count))
            }

            result[ch] = peaks
        }

        return result
    }
}
