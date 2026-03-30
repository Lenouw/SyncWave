// Sources/SyncWave/Engine/ExportEngine.swift
import Foundation

struct ExportEngine {

    enum ExportError: Error, LocalizedError {
        case noClips
        case writeError(path: String, underlying: Error)

        var errorDescription: String? {
            switch self {
            case .noClips: return "Aucun clip à exporter"
            case .writeError(let path, let err): return "Erreur écriture \(path): \(err.localizedDescription)"
            }
        }
    }

    // MARK: - Public API

    /// Generate FCP 7 XML from SyncWave tracks.
    /// Rule: 1 Premiere audio track per SyncWave source track.
    ///   SyncWave V1 → Premiere V1 (video) + A1 (audio)
    ///   SyncWave VN → Premiere VN (video) + AN (audio)
    ///   SyncWave A1 → Premiere A(numVideoTracks+1)
    /// → N video tracks + M audio tracks = N+M total Premiere audio tracks
    func generateTrackBasedXML(tracks: [Track], syncedClips: [MediaClip], settings: ExportSettings, frameRate: Int = 30, sequenceWidth: Int = 1920, sequenceHeight: Int = 1080) throws -> String {
        let ntsc = (frameRate == 25 || frameRate == 50) ? "FALSE" : "TRUE"

        var offsetMap: [UUID: TimeInterval] = [:]
        for clip in syncedClips { offsetMap[clip.id] = clip.offset ?? 0 }

        let allOffsets = syncedClips.compactMap { $0.offset }
        let minOffset = allOffsets.min() ?? 0

        let videoTracks = tracks.filter { $0.type == .video && !$0.clips.isEmpty }
        let audioOnlyTracks = tracks.filter { $0.type == .audio && !$0.clips.isEmpty }

        var clipItemCounter = 1
        var fileCounter = 1
        var masterClipCounter = 1

        func nextClipItemID() -> String {
            let id = "clipitem-\(clipItemCounter)"; clipItemCounter += 1; return id
        }

        var videoTracksXML = ""
        var audioTracksXML = ""
        var premiereVideoTrackIndex = 0
        var premiereAudioTrackIndex = 0

        // MARK: - Video tracks → 1 audio track each

        for vTrack in videoTracks {
            premiereVideoTrackIndex += 1
            premiereAudioTrackIndex += 1
            let audioTrackIdx = premiereAudioTrackIndex
            let sortedClips = vTrack.clips.sorted { (offsetMap[$0.id] ?? 0) < (offsetMap[$1.id] ?? 0) }

            videoTracksXML += "        <track>\n"
            var audioTrackXML = "        <track>\n"

            for (clipIndexOnTrack, clip) in sortedClips.enumerated() {
                let clipIdx = clipIndexOnTrack + 1
                let offset = (offsetMap[clip.id] ?? 0) - minOffset
                let startFrame = Int(offset * Double(frameRate))
                let durationFrames = Int(clip.duration * Double(frameRate))
                let fileID = "file-\(fileCounter)"
                let masterID = "masterclip-\(masterClipCounter)"
                let videoItemID = nextClipItemID()
                let audioItemID = nextClipItemID()
                fileCounter += 1; masterClipCounter += 1

                let fileXML = buildFileElement(clip: clip, fileID: fileID, frameRate: frameRate, ntsc: ntsc, full: true)
                let fileRef = "<file id=\"\(fileID)\"/>"

                videoTracksXML += clipItemXML(
                    id: videoItemID, masterID: masterID, name: clip.filename,
                    start: startFrame, duration: durationFrames, frameRate: frameRate, ntsc: ntsc,
                    fileContent: fileXML,
                    links: [
                        (ref: videoItemID, type: "video", trackIdx: premiereVideoTrackIndex, clipIdx: clipIdx, group: nil),
                        (ref: audioItemID, type: "audio", trackIdx: audioTrackIdx,           clipIdx: clipIdx, group: 1),
                    ]
                )
                audioTrackXML += clipItemXML(
                    id: audioItemID, masterID: masterID, name: clip.filename,
                    start: startFrame, duration: durationFrames, frameRate: frameRate, ntsc: ntsc,
                    fileContent: fileRef, sourceTrack: 1,
                    links: [
                        (ref: videoItemID, type: "video", trackIdx: premiereVideoTrackIndex, clipIdx: clipIdx, group: nil),
                        (ref: audioItemID, type: "audio", trackIdx: audioTrackIdx,           clipIdx: clipIdx, group: 1),
                    ]
                )
            }

            videoTracksXML += "          <enabled>TRUE</enabled>\n          <locked>FALSE</locked>\n        </track>\n\n"
            audioTrackXML += "          <enabled>TRUE</enabled>\n          <locked>FALSE</locked>\n"
            audioTrackXML += "          <outputchannelindex>\(audioTrackIdx)</outputchannelindex>\n        </track>\n\n"
            audioTracksXML += audioTrackXML
        }

        // MARK: - Standalone audio tracks → 1 track each

        for aTrack in audioOnlyTracks {
            premiereAudioTrackIndex += 1
            let audioTrackIdx = premiereAudioTrackIndex
            let sortedClips = aTrack.clips.sorted { (offsetMap[$0.id] ?? 0) < (offsetMap[$1.id] ?? 0) }
            var audioTrackXML = "        <track>\n"

            for (clipIndexOnTrack, clip) in sortedClips.enumerated() {
                let clipIdx = clipIndexOnTrack + 1
                let offset = (offsetMap[clip.id] ?? 0) - minOffset
                let startFrame = Int(offset * Double(frameRate))
                let durationFrames = Int(clip.duration * Double(frameRate))
                let fileID = "file-\(fileCounter)"
                let masterID = "masterclip-\(masterClipCounter)"
                let audioItemID = nextClipItemID()
                fileCounter += 1; masterClipCounter += 1

                let fileXML = buildFileElement(clip: clip, fileID: fileID, frameRate: frameRate, ntsc: ntsc, full: true)
                audioTrackXML += clipItemXML(
                    id: audioItemID, masterID: masterID, name: clip.filename,
                    start: startFrame, duration: durationFrames, frameRate: frameRate, ntsc: ntsc,
                    fileContent: fileXML,
                    links: [(ref: audioItemID, type: "audio", trackIdx: audioTrackIdx, clipIdx: clipIdx, group: 1)]
                )
            }
            audioTrackXML += "          <enabled>TRUE</enabled>\n          <locked>FALSE</locked>\n"
            audioTrackXML += "          <outputchannelindex>\(audioTrackIdx)</outputchannelindex>\n        </track>\n\n"
            audioTracksXML += audioTrackXML
        }

        // Outputs: 1 mono group per audio track
        var outputsXML = ""
        if premiereAudioTrackIndex > 0 {
            for i in 1...premiereAudioTrackIndex {
                outputsXML += "          <group>\n"
                outputsXML += "            <index>\(i)</index>\n"
                outputsXML += "            <numchannels>1</numchannels>\n"
                outputsXML += "            <downmix>0</downmix>\n"
                outputsXML += "            <channel><index>\(i)</index></channel>\n"
                outputsXML += "          </group>\n"
            }
        }

        let totalOutputChannels = premiereAudioTrackIndex

        // Total duration
        let allEnds = syncedClips.map { (($0.offset ?? 0) - minOffset + $0.duration) * Double(frameRate) }
        let totalDurationFrames = Int(allEnds.max() ?? 0)

        return buildSequenceXML(
            frameRate: frameRate, ntsc: ntsc,
            width: sequenceWidth, height: sequenceHeight,
            totalDurationFrames: totalDurationFrames,
            totalOutputChannels: totalOutputChannels,
            videoTracksXML: videoTracksXML,
            audioTracksXML: audioTracksXML,
            outputsXML: outputsXML
        )
    }

    func exportToFile(xml: String, directory: URL, filename: String = "SyncWave Export.xml") throws -> URL {
        let outputURL = directory.appendingPathComponent(filename)
        do { try xml.write(to: outputURL, atomically: true, encoding: .utf8) }
        catch { throw ExportError.writeError(path: outputURL.path, underlying: error) }
        return outputURL
    }

    // MARK: - XML helpers

    private func clipItemXML(
        id: String, masterID: String, name: String,
        start: Int, duration: Int, frameRate: Int, ntsc: String,
        fileContent: String, sourceTrack: Int? = nil,
        links: [(ref: String, type: String, trackIdx: Int, clipIdx: Int, group: Int?)]
    ) -> String {
        var xml = "          <clipitem id=\"\(id)\">\n"
        xml += "            <masterclipid>\(masterID)</masterclipid>\n"
        xml += "            <name>\(escapeXML(name))</name>\n"
        xml += "            <enabled>TRUE</enabled>\n"
        xml += "            <duration>\(duration)</duration>\n"
        xml += "            <rate><timebase>\(frameRate)</timebase><ntsc>\(ntsc)</ntsc></rate>\n"
        xml += "            <start>\(start)</start>\n"
        xml += "            <end>\(start + duration)</end>\n"
        xml += "            <in>0</in>\n"
        xml += "            <out>\(duration)</out>\n"
        xml += "            \(fileContent)\n"

        if let st = sourceTrack {
            xml += "            <sourcetrack><mediatype>audio</mediatype><trackindex>\(st)</trackindex></sourcetrack>\n"
        }

        for link in links {
            xml += "            <link>\n"
            xml += "              <linkclipref>\(link.ref)</linkclipref>\n"
            xml += "              <mediatype>\(link.type)</mediatype>\n"
            xml += "              <trackindex>\(link.trackIdx)</trackindex>\n"
            xml += "              <clipindex>\(link.clipIdx)</clipindex>\n"
            if let g = link.group {
                xml += "              <groupindex>\(g)</groupindex>\n"
            }
            xml += "            </link>\n"
        }

        xml += "          </clipitem>\n"
        return xml
    }

    private func buildFileElement(clip: MediaClip, fileID: String, frameRate: Int, ntsc: String, full: Bool) -> String {
        guard full else { return "<file id=\"\(fileID)\"/>" }

        let path = clip.url.path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? clip.url.path
        let dur = Int(clip.duration * Double(frameRate))
        var xml = "<file id=\"\(fileID)\">"
        xml += "<name>\(escapeXML(clip.filename))</name>"
        xml += "<pathurl>file://localhost\(path)</pathurl>"
        xml += "<rate><timebase>\(frameRate)</timebase><ntsc>\(ntsc)</ntsc></rate>"
        xml += "<duration>\(dur)</duration>"
        xml += "<timecode><rate><timebase>\(frameRate)</timebase><ntsc>\(ntsc)</ntsc></rate>"
        xml += "<string>00:00:00:00</string><frame>0</frame><displayformat>NDF</displayformat></timecode>"
        xml += "<media>"
        if clip.isVideo {
            let w = clip.videoWidth > 0 ? clip.videoWidth : 1920
            let h = clip.videoHeight > 0 ? clip.videoHeight : 1080
            xml += "<video><samplecharacteristics>"
            xml += "<rate><timebase>\(frameRate)</timebase><ntsc>\(ntsc)</ntsc></rate>"
            xml += "<width>\(w)</width><height>\(h)</height>"
            xml += "<anamorphic>FALSE</anamorphic><pixelaspectratio>square</pixelaspectratio>"
            xml += "<fielddominance>none</fielddominance>"
            xml += "</samplecharacteristics></video>"
        }
        let channelCount = clip.audioChannelCount > 0 ? clip.audioChannelCount : (clip.isVideo ? 2 : 1)
        xml += "<audio><samplecharacteristics><depth>16</depth><samplerate>48000</samplerate>"
        xml += "</samplecharacteristics><channelcount>\(channelCount)</channelcount></audio>"
        xml += "</media></file>"
        return xml
    }

    private func buildSequenceXML(frameRate: Int, ntsc: String, width: Int, height: Int, totalDurationFrames: Int, totalOutputChannels: Int = 2, videoTracksXML: String, audioTracksXML: String, outputsXML: String) -> String {
        var xml = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<!DOCTYPE xmeml>\n<xmeml version=\"4\">\n"
        xml += "  <sequence id=\"sequence-1\">\n"
        xml += "    <uuid>\(UUID().uuidString)</uuid>\n"
        xml += "    <name>SyncWave Export</name>\n"
        xml += "    <duration>\(totalDurationFrames)</duration>\n"
        xml += "    <rate><timebase>\(frameRate)</timebase><ntsc>\(ntsc)</ntsc></rate>\n"
        xml += "    <timecode><rate><timebase>\(frameRate)</timebase><ntsc>\(ntsc)</ntsc></rate>\n"
        xml += "      <string>00:00:00:00</string><frame>0</frame><displayformat>NDF</displayformat></timecode>\n"
        xml += "    <media>\n"
        xml += "      <video>\n"
        xml += "        <format><samplecharacteristics>\n"
        xml += "          <rate><timebase>\(frameRate)</timebase><ntsc>\(ntsc)</ntsc></rate>\n"
        xml += "          <width>\(width)</width><height>\(height)</height>\n"
        xml += "          <anamorphic>FALSE</anamorphic><pixelaspectratio>square</pixelaspectratio>\n"
        xml += "          <fielddominance>none</fielddominance><colordepth>24</colordepth>\n"
        xml += "        </samplecharacteristics></format>\n"
        xml += videoTracksXML
        xml += "      </video>\n"
        xml += "      <audio>\n"
        xml += "        <numOutputChannels>\(totalOutputChannels)</numOutputChannels>\n"
        xml += "        <format><samplecharacteristics><depth>16</depth><samplerate>48000</samplerate></samplecharacteristics></format>\n"
        xml += "        <outputs>\n\(outputsXML)        </outputs>\n"
        xml += audioTracksXML
        xml += "      </audio>\n"
        xml += "    </media>\n"
        xml += "  </sequence>\n</xmeml>\n"
        return xml
    }

    private func escapeXML(_ string: String) -> String {
        string.replacingOccurrences(of: "&", with: "&amp;")
              .replacingOccurrences(of: "<", with: "&lt;")
              .replacingOccurrences(of: ">", with: "&gt;")
              .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
