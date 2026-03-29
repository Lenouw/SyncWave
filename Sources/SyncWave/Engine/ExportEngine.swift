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
    /// Maps SyncWave tracks to Premiere tracks:
    ///   SyncWave V1 → Premiere V1 (video) + A1 (audio stereo)
    ///   SyncWave V2 → Premiere V2 (video) + A2 (audio stereo)
    ///   SyncWave A1 → Premiere A(N+1) (audio only, stereo)
    ///   SyncWave A2 → Premiere A(N+2) (audio only, stereo)
    func generateTrackBasedXML(tracks: [Track], syncedClips: [MediaClip], settings: ExportSettings, frameRate: Int = 30) throws -> String {
        // NTSC: 25fps and 50fps are non-NTSC. All others (23.976→24, 29.97→30, 59.94→60) are NTSC.
        let ntsc = (frameRate == 25 || frameRate == 50) ? "FALSE" : "TRUE"

        // Build offset map from synced clips
        var offsetMap: [UUID: TimeInterval] = [:]
        for clip in syncedClips {
            offsetMap[clip.id] = clip.offset ?? 0
        }

        // Normalize offsets so minimum = 0
        let allOffsets = syncedClips.compactMap { $0.offset }
        let minOffset = allOffsets.min() ?? 0

        // Separate video and audio tracks
        let videoTracks = tracks.filter { $0.type == .video && !$0.clips.isEmpty }
        let audioOnlyTracks = tracks.filter { $0.type == .audio && !$0.clips.isEmpty }

        // Counters
        var clipItemCounter = 1
        var fileCounter = 1
        var masterClipCounter = 1

        func nextClipItemID() -> String {
            let id = "clipitem-\(clipItemCounter)"
            clipItemCounter += 1
            return id
        }

        // MARK: - Build video tracks XML
        // Each SyncWave video track → one Premiere <track> in <video>
        // with multiple <clipitem> for each clip on that track

        var videoTracksXML = ""
        var audioTracksXML = ""
        var premiereVideoTrackIndex = 0  // V1, V2...
        var premiereAudioTrackIndex = 0  // A1, A2... (pairs for stereo)

        // Track file definitions (first occurrence gets full definition, rest get reference)

        for vTrack in videoTracks {
            premiereVideoTrackIndex += 1
            premiereAudioTrackIndex += 1  // A(N) paired with V(N)
            let audioChBaseIndex = (premiereAudioTrackIndex - 1) * 2 + 1  // 1-based stereo pair

            // Video track with all clips
            videoTracksXML += "        <track>\n"
            // Audio tracks (ch1 and ch2) with all clips
            var audioCh1XML = "        <track>\n"
            var audioCh2XML = "        <track>\n"

            for (clipIndexOnTrack, clip) in vTrack.clips.enumerated() {
                let clipIdx = clipIndexOnTrack + 1  // 1-based clip index on this track
                let offset = (offsetMap[clip.id] ?? 0) - minOffset
                let startFrame = Int(offset * Double(frameRate))
                let durationFrames = Int(clip.duration * Double(frameRate))
                let fileID = "file-\(fileCounter)"
                let masterID = "masterclip-\(masterClipCounter)"
                let videoItemID = nextClipItemID()
                let audioCh1ItemID = nextClipItemID()
                let audioCh2ItemID = nextClipItemID()
                fileCounter += 1
                masterClipCounter += 1

                let fileXML = buildFileElement(clip: clip, fileID: fileID, frameRate: frameRate, ntsc: ntsc, full: true)
                let fileRef = "<file id=\"\(fileID)\"/>"

                // Video clipitem
                videoTracksXML += clipItemXML(
                    id: videoItemID, masterID: masterID, name: clip.filename,
                    start: startFrame, duration: durationFrames, frameRate: frameRate, ntsc: ntsc,
                    fileContent: fileXML,
                    links: [
                        (ref: videoItemID, type: "video", trackIdx: premiereVideoTrackIndex, clipIdx: clipIdx, group: nil),
                        (ref: audioCh1ItemID, type: "audio", trackIdx: audioChBaseIndex, clipIdx: clipIdx, group: 1),
                        (ref: audioCh2ItemID, type: "audio", trackIdx: audioChBaseIndex + 1, clipIdx: clipIdx, group: 2),
                    ]
                )

                // Audio ch1 clipitem
                audioCh1XML += clipItemXML(
                    id: audioCh1ItemID, masterID: masterID, name: clip.filename,
                    start: startFrame, duration: durationFrames, frameRate: frameRate, ntsc: ntsc,
                    fileContent: fileRef, sourceTrack: 1,
                    links: [
                        (ref: videoItemID, type: "video", trackIdx: premiereVideoTrackIndex, clipIdx: clipIdx, group: nil),
                        (ref: audioCh1ItemID, type: "audio", trackIdx: audioChBaseIndex, clipIdx: clipIdx, group: 1),
                        (ref: audioCh2ItemID, type: "audio", trackIdx: audioChBaseIndex + 1, clipIdx: clipIdx, group: 2),
                    ]
                )

                // Audio ch2 clipitem
                audioCh2XML += clipItemXML(
                    id: audioCh2ItemID, masterID: masterID, name: clip.filename,
                    start: startFrame, duration: durationFrames, frameRate: frameRate, ntsc: ntsc,
                    fileContent: fileRef, sourceTrack: 2,
                    links: [
                        (ref: videoItemID, type: "video", trackIdx: premiereVideoTrackIndex, clipIdx: clipIdx, group: nil),
                        (ref: audioCh1ItemID, type: "audio", trackIdx: audioChBaseIndex, clipIdx: clipIdx, group: 1),
                        (ref: audioCh2ItemID, type: "audio", trackIdx: audioChBaseIndex + 1, clipIdx: clipIdx, group: 2),
                    ]
                )
            }

            videoTracksXML += "          <enabled>TRUE</enabled>\n          <locked>FALSE</locked>\n        </track>\n\n"
            audioCh1XML += "          <enabled>TRUE</enabled>\n          <locked>FALSE</locked>\n"
            audioCh1XML += "          <outputchannelindex>\(audioChBaseIndex)</outputchannelindex>\n        </track>\n\n"
            audioCh2XML += "          <enabled>TRUE</enabled>\n          <locked>FALSE</locked>\n"
            audioCh2XML += "          <outputchannelindex>\(audioChBaseIndex + 1)</outputchannelindex>\n        </track>\n\n"

            audioTracksXML += audioCh1XML
            audioTracksXML += audioCh2XML
        }

        // MARK: - Build audio-only tracks XML
        // Each SyncWave audio track → Premiere A(N+1) (no video track)

        for aTrack in audioOnlyTracks {
            premiereAudioTrackIndex += 1
            let audioChBaseIndex = (premiereAudioTrackIndex - 1) * 2 + 1

            var audioCh1XML = "        <track>\n"
            var audioCh2XML = "        <track>\n"

            for (clipIndexOnTrack, clip) in aTrack.clips.enumerated() {
                let clipIdx = clipIndexOnTrack + 1
                let offset = (offsetMap[clip.id] ?? 0) - minOffset
                let startFrame = Int(offset * Double(frameRate))
                let durationFrames = Int(clip.duration * Double(frameRate))
                let fileID = "file-\(fileCounter)"
                let masterID = "masterclip-\(masterClipCounter)"
                let audioCh1ItemID = nextClipItemID()
                let audioCh2ItemID = nextClipItemID()
                fileCounter += 1
                masterClipCounter += 1

                let fileXML = buildFileElement(clip: clip, fileID: fileID, frameRate: frameRate, ntsc: ntsc, full: true)
                let fileRef = "<file id=\"\(fileID)\"/>"

                // Audio ch1
                audioCh1XML += clipItemXML(
                    id: audioCh1ItemID, masterID: masterID, name: clip.filename,
                    start: startFrame, duration: durationFrames, frameRate: frameRate, ntsc: ntsc,
                    fileContent: fileXML, sourceTrack: 1,
                    links: [
                        (ref: audioCh1ItemID, type: "audio", trackIdx: audioChBaseIndex, clipIdx: clipIdx, group: 1),
                        (ref: audioCh2ItemID, type: "audio", trackIdx: audioChBaseIndex + 1, clipIdx: clipIdx, group: 2),
                    ]
                )

                // Audio ch2
                audioCh2XML += clipItemXML(
                    id: audioCh2ItemID, masterID: masterID, name: clip.filename,
                    start: startFrame, duration: durationFrames, frameRate: frameRate, ntsc: ntsc,
                    fileContent: fileRef, sourceTrack: 2,
                    links: [
                        (ref: audioCh1ItemID, type: "audio", trackIdx: audioChBaseIndex, clipIdx: clipIdx, group: 1),
                        (ref: audioCh2ItemID, type: "audio", trackIdx: audioChBaseIndex + 1, clipIdx: clipIdx, group: 2),
                    ]
                )
            }

            audioCh1XML += "          <enabled>TRUE</enabled>\n          <locked>FALSE</locked>\n"
            audioCh1XML += "          <outputchannelindex>\(audioChBaseIndex)</outputchannelindex>\n        </track>\n\n"
            audioCh2XML += "          <enabled>TRUE</enabled>\n          <locked>FALSE</locked>\n"
            audioCh2XML += "          <outputchannelindex>\(audioChBaseIndex + 1)</outputchannelindex>\n        </track>\n\n"

            audioTracksXML += audioCh1XML
            audioTracksXML += audioCh2XML
        }

        // Build outputs
        var outputsXML = ""
        for i in 1...premiereAudioTrackIndex {
            let base = (i - 1) * 2 + 1
            outputsXML += "          <group>\n"
            outputsXML += "            <index>\(base)</index>\n"
            outputsXML += "            <numchannels>2</numchannels>\n"
            outputsXML += "            <downmix>0</downmix>\n"
            outputsXML += "            <channel><index>\(base)</index></channel>\n"
            outputsXML += "            <channel><index>\(base + 1)</index></channel>\n"
            outputsXML += "          </group>\n"
        }

        // Total duration
        let allEnds = syncedClips.map { (($0.offset ?? 0) - minOffset + $0.duration) * Double(frameRate) }
        let totalDurationFrames = Int(allEnds.max() ?? 0)

        return buildSequenceXML(
            frameRate: frameRate, ntsc: ntsc,
            totalDurationFrames: totalDurationFrames,
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
            xml += "<video><samplecharacteristics>"
            xml += "<rate><timebase>\(frameRate)</timebase><ntsc>\(ntsc)</ntsc></rate>"
            xml += "<width>1920</width><height>1080</height>"
            xml += "<anamorphic>FALSE</anamorphic><pixelaspectratio>square</pixelaspectratio>"
            xml += "<fielddominance>none</fielddominance>"
            xml += "</samplecharacteristics></video>"
        }
        xml += "<audio><samplecharacteristics><depth>16</depth><samplerate>48000</samplerate>"
        xml += "</samplecharacteristics><channelcount>2</channelcount></audio>"
        xml += "</media></file>"
        return xml
    }

    private func buildSequenceXML(frameRate: Int, ntsc: String, totalDurationFrames: Int, videoTracksXML: String, audioTracksXML: String, outputsXML: String) -> String {
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
        xml += "          <width>1920</width><height>1080</height>\n"
        xml += "          <anamorphic>FALSE</anamorphic><pixelaspectratio>square</pixelaspectratio>\n"
        xml += "          <fielddominance>none</fielddominance><colordepth>24</colordepth>\n"
        xml += "        </samplecharacteristics></format>\n"
        xml += videoTracksXML
        xml += "      </video>\n"
        xml += "      <audio>\n"
        xml += "        <numOutputChannels>2</numOutputChannels>\n"
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
