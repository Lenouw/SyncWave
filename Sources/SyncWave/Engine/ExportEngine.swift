// Sources/SyncWave/Engine/ExportEngine.swift
import Foundation

struct ExportEngine {

    enum ExportError: Error, LocalizedError {
        case noReferenceClip
        case writeError(path: String, underlying: Error)

        var errorDescription: String? {
            switch self {
            case .noReferenceClip: return "Clip de référence introuvable"
            case .writeError(let path, let err): return "Erreur écriture \(path): \(err.localizedDescription)"
            }
        }
    }

    func generateFCP7XML(clips: [MediaClip], syncResult: SyncResult, settings: ExportSettings, frameRate: Int = 25) throws -> String {
        guard let referenceClip = clips.first(where: { $0.id == syncResult.referenceClipID }) else {
            throw ExportError.noReferenceClip
        }

        let alignmentMap = Dictionary(uniqueKeysWithValues: syncResult.alignments.map { ($0.clipID, $0) })
        var tracks = ""

        // Reference clip at offset 0
        let refDurationFrames = Int(referenceClip.duration * Double(frameRate))
        tracks += videoTrackXML(clip: referenceClip, startFrame: 0, durationFrames: refDurationFrames, frameRate: frameRate, fileID: "file-\(referenceClip.id.uuidString.prefix(8))")

        // Aligned clips
        for clip in clips where clip.id != syncResult.referenceClipID {
            guard let alignment = alignmentMap[clip.id] else { continue }
            if !settings.includeUnsyncedClips && alignment.confidence < 0.3 { continue }

            let offsetFrames = Int(alignment.offset * Double(frameRate))
            let durationFrames = Int(clip.duration * Double(frameRate))

            if clip.isVideo {
                tracks += videoTrackXML(clip: clip, startFrame: offsetFrames, durationFrames: durationFrames, frameRate: frameRate, fileID: "file-\(clip.id.uuidString.prefix(8))")
            } else {
                tracks += audioTrackXML(clip: clip, startFrame: offsetFrames, durationFrames: durationFrames, frameRate: frameRate, fileID: "file-\(clip.id.uuidString.prefix(8))")
            }
        }

        let totalDurationFrames = Int((clips.map(\.duration).max() ?? 0) * Double(frameRate))

        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <xmeml version="5">
          <sequence>
            <name>SyncWave Export</name>
            <duration>\(totalDurationFrames)</duration>
            <rate>
              <timebase>\(frameRate)</timebase>
              <ntsc>FALSE</ntsc>
            </rate>
            <media>
              \(tracks)
            </media>
          </sequence>
        </xmeml>
        """
    }

    func exportToFile(xml: String, directory: URL, filename: String = "SyncWave Export.xml") throws -> URL {
        let outputURL = directory.appendingPathComponent(filename)
        do { try xml.write(to: outputURL, atomically: true, encoding: .utf8) }
        catch { throw ExportError.writeError(path: outputURL.path, underlying: error) }
        return outputURL
    }

    private func videoTrackXML(clip: MediaClip, startFrame: Int, durationFrames: Int, frameRate: Int, fileID: String) -> String {
        """
        <video>
          <track>
            <clipitem>
              <name>\(escapeXML(clip.filename))</name>
              <duration>\(durationFrames)</duration>
              <start>\(startFrame)</start>
              <end>\(startFrame + durationFrames)</end>
              <in>0</in>
              <out>\(durationFrames)</out>
              <file id="\(fileID)">
                <name>\(escapeXML(clip.filename))</name>
                <pathurl>file://\(escapeXML(clip.url.path))</pathurl>
                <duration>\(durationFrames)</duration>
                <rate><timebase>\(frameRate)</timebase></rate>
              </file>
            </clipitem>
          </track>
        </video>
        """
    }

    private func audioTrackXML(clip: MediaClip, startFrame: Int, durationFrames: Int, frameRate: Int, fileID: String) -> String {
        """
        <audio>
          <track>
            <clipitem>
              <name>\(escapeXML(clip.filename))</name>
              <duration>\(durationFrames)</duration>
              <start>\(startFrame)</start>
              <end>\(startFrame + durationFrames)</end>
              <in>0</in>
              <out>\(durationFrames)</out>
              <file id="\(fileID)">
                <name>\(escapeXML(clip.filename))</name>
                <pathurl>file://\(escapeXML(clip.url.path))</pathurl>
                <duration>\(durationFrames)</duration>
                <rate><timebase>\(frameRate)</timebase></rate>
              </file>
            </clipitem>
          </track>
        </audio>
        """
    }

    private func escapeXML(_ string: String) -> String {
        string.replacingOccurrences(of: "&", with: "&amp;")
              .replacingOccurrences(of: "<", with: "&lt;")
              .replacingOccurrences(of: ">", with: "&gt;")
              .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
