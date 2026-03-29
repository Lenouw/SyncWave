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

    // MARK: - Private model

    private struct TrackEntry {
        let clip: MediaClip
        let startFrame: Int
        let durationFrames: Int
        let fileID: String
        let masterClipID: String
        let videoClipItemID: String      // empty string if audio-only
        let audioClipItemCh1ID: String
        let audioClipItemCh2ID: String
        let videoTrackIndex: Int         // 0 if audio-only
        let audioTrackCh1Index: Int
        let audioTrackCh2Index: Int
    }

    // MARK: - Public API

    func generateFCP7XML(clips: [MediaClip], syncResult: SyncResult, settings: ExportSettings, frameRate: Int = 30) throws -> String {
        guard let referenceClip = clips.first(where: { $0.id == syncResult.referenceClipID }) else {
            throw ExportError.noReferenceClip
        }

        // Use uniquingKeysWith to handle duplicate clip IDs (same file on multiple tracks)
        let alignmentMap = Dictionary(syncResult.alignments.map { ($0.clipID, $0) }, uniquingKeysWith: { first, _ in first })
        let ntsc = (frameRate == 30 || frameRate == 60 || frameRate == 24) ? "TRUE" : "FALSE"

        let entries = buildEntries(
            referenceClip: referenceClip,
            clips: clips,
            alignmentMap: alignmentMap,
            settings: settings,
            frameRate: frameRate
        )

        let totalDurationFrames = entries.map { $0.startFrame + $0.durationFrames }.max() ?? 0

        var videoTracksXML = ""
        for entry in entries where entry.clip.isVideo {
            videoTracksXML += buildVideoTrack(entry: entry, frameRate: frameRate, ntsc: ntsc)
        }

        var audioTracksXML = ""
        for entry in entries {
            // For video clips, file is already defined in the video track
            audioTracksXML += buildAudioTrack(entry: entry, channel: 1, frameRate: frameRate, ntsc: ntsc, fileAlreadyDefined: entry.clip.isVideo)
            // ch2 always references — file already defined either in video track or in ch1
            audioTracksXML += buildAudioTrack(entry: entry, channel: 2, frameRate: frameRate, ntsc: ntsc, fileAlreadyDefined: true)
        }

        let outputsXML = buildAudioOutputs(entries: entries)

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

    // MARK: - Entry construction

    private func buildEntries(
        referenceClip: MediaClip,
        clips: [MediaClip],
        alignmentMap: [UUID: ClipAlignment],
        settings: ExportSettings,
        frameRate: Int
    ) -> [TrackEntry] {
        var entries: [TrackEntry] = []
        var clipItemCounter = 1
        var videoTrackCounter = 1
        var audioTrackCounter = 1

        func nextClipItemID() -> String {
            let id = "clipitem-\(clipItemCounter)"
            clipItemCounter += 1
            return id
        }

        func makeEntry(_ clip: MediaClip, startFrame: Int, index: Int) -> TrackEntry {
            let fileID = "file-\(index)"
            let masterClipID = "masterclip-\(index)"

            let videoClipItemID: String
            let videoTrackIndex: Int
            if clip.isVideo {
                videoClipItemID = nextClipItemID()
                videoTrackIndex = videoTrackCounter
                videoTrackCounter += 1
            } else {
                videoClipItemID = ""
                videoTrackIndex = 0
            }

            let audioClipItemCh1ID = nextClipItemID()
            let audioClipItemCh2ID = nextClipItemID()
            let audioTrackCh1Index = audioTrackCounter
            audioTrackCounter += 1
            let audioTrackCh2Index = audioTrackCounter
            audioTrackCounter += 1

            return TrackEntry(
                clip: clip,
                startFrame: startFrame,
                durationFrames: Int(clip.duration * Double(frameRate)),
                fileID: fileID,
                masterClipID: masterClipID,
                videoClipItemID: videoClipItemID,
                audioClipItemCh1ID: audioClipItemCh1ID,
                audioClipItemCh2ID: audioClipItemCh2ID,
                videoTrackIndex: videoTrackIndex,
                audioTrackCh1Index: audioTrackCh1Index,
                audioTrackCh2Index: audioTrackCh2Index
            )
        }

        // Collect raw offsets first
        var rawOffsets: [(clip: MediaClip, offsetFrames: Int, index: Int)] = []
        rawOffsets.append((clip: referenceClip, offsetFrames: 0, index: 1))

        var idx = 2
        for clip in clips where clip.id != referenceClip.id {
            guard let alignment = alignmentMap[clip.id] else { continue }
            if !settings.includeUnsyncedClips && alignment.confidence < 0.3 { continue }
            let offsetFrames = Int(alignment.offset * Double(frameRate))
            rawOffsets.append((clip: clip, offsetFrames: offsetFrames, index: idx))
            idx += 1
        }

        // Normalize: shift all clips so the earliest starts at frame 0
        let minOffset = rawOffsets.map(\.offsetFrames).min() ?? 0
        for item in rawOffsets {
            entries.append(makeEntry(item.clip, startFrame: item.offsetFrames - minOffset, index: item.index))
        }

        return entries
    }

    // MARK: - XML builders

    private func buildVideoTrack(entry: TrackEntry, frameRate: Int, ntsc: String) -> String {
        let name = escapeXML(entry.clip.filename)
        let start = entry.startFrame
        let end = start + entry.durationFrames
        let dur = entry.durationFrames
        let fileXML = buildFileElementFull(entry: entry, frameRate: frameRate, ntsc: ntsc)

        var xml = "        <track>\n"
        xml += "          <clipitem id=\"\(entry.videoClipItemID)\">\n"
        xml += "            <masterclipid>\(entry.masterClipID)</masterclipid>\n"
        xml += "            <name>\(name)</name>\n"
        xml += "            <enabled>TRUE</enabled>\n"
        xml += "            <duration>\(dur)</duration>\n"
        xml += "            <rate>\n"
        xml += "              <timebase>\(frameRate)</timebase>\n"
        xml += "              <ntsc>\(ntsc)</ntsc>\n"
        xml += "            </rate>\n"
        xml += "            <start>\(start)</start>\n"
        xml += "            <end>\(end)</end>\n"
        xml += "            <in>0</in>\n"
        xml += "            <out>\(dur)</out>\n"
        xml += "            \(fileXML)\n"
        // Link: video -> self
        xml += "            <link>\n"
        xml += "              <linkclipref>\(entry.videoClipItemID)</linkclipref>\n"
        xml += "              <mediatype>video</mediatype>\n"
        xml += "              <trackindex>\(entry.videoTrackIndex)</trackindex>\n"
        xml += "              <clipindex>1</clipindex>\n"
        xml += "            </link>\n"
        // Link: video -> audio ch1
        xml += "            <link>\n"
        xml += "              <linkclipref>\(entry.audioClipItemCh1ID)</linkclipref>\n"
        xml += "              <mediatype>audio</mediatype>\n"
        xml += "              <trackindex>\(entry.audioTrackCh1Index)</trackindex>\n"
        xml += "              <clipindex>1</clipindex>\n"
        xml += "              <groupindex>1</groupindex>\n"
        xml += "            </link>\n"
        // Link: video -> audio ch2
        xml += "            <link>\n"
        xml += "              <linkclipref>\(entry.audioClipItemCh2ID)</linkclipref>\n"
        xml += "              <mediatype>audio</mediatype>\n"
        xml += "              <trackindex>\(entry.audioTrackCh2Index)</trackindex>\n"
        xml += "              <clipindex>1</clipindex>\n"
        xml += "              <groupindex>2</groupindex>\n"
        xml += "            </link>\n"
        xml += "          </clipitem>\n"
        xml += "          <enabled>TRUE</enabled>\n"
        xml += "          <locked>FALSE</locked>\n"
        xml += "        </track>\n\n"
        return xml
    }

    private func buildAudioTrack(entry: TrackEntry, channel: Int, frameRate: Int, ntsc: String, fileAlreadyDefined: Bool) -> String {
        let name = escapeXML(entry.clip.filename)
        let start = entry.startFrame
        let end = start + entry.durationFrames
        let dur = entry.durationFrames
        let clipItemID = channel == 1 ? entry.audioClipItemCh1ID : entry.audioClipItemCh2ID
        let outputChannelIndex = channel == 1 ? entry.audioTrackCh1Index : entry.audioTrackCh2Index

        let fileRef: String
        if fileAlreadyDefined {
            fileRef = "<file id=\"\(entry.fileID)\"/>"
        } else {
            fileRef = buildFileElementFull(entry: entry, frameRate: frameRate, ntsc: ntsc)
        }

        var xml = "        <track>\n"
        xml += "          <clipitem id=\"\(clipItemID)\">\n"
        xml += "            <masterclipid>\(entry.masterClipID)</masterclipid>\n"
        xml += "            <name>\(name)</name>\n"
        xml += "            <enabled>TRUE</enabled>\n"
        xml += "            <duration>\(dur)</duration>\n"
        xml += "            <rate>\n"
        xml += "              <timebase>\(frameRate)</timebase>\n"
        xml += "              <ntsc>\(ntsc)</ntsc>\n"
        xml += "            </rate>\n"
        xml += "            <start>\(start)</start>\n"
        xml += "            <end>\(end)</end>\n"
        xml += "            <in>0</in>\n"
        xml += "            <out>\(dur)</out>\n"
        xml += "            \(fileRef)\n"
        xml += "            <sourcetrack>\n"
        xml += "              <mediatype>audio</mediatype>\n"
        xml += "              <trackindex>\(channel)</trackindex>\n"
        xml += "            </sourcetrack>\n"
        // Link: audio -> video (only for video clips)
        if entry.clip.isVideo {
            xml += "            <link>\n"
            xml += "              <linkclipref>\(entry.videoClipItemID)</linkclipref>\n"
            xml += "              <mediatype>video</mediatype>\n"
            xml += "              <trackindex>\(entry.videoTrackIndex)</trackindex>\n"
            xml += "              <clipindex>1</clipindex>\n"
            xml += "            </link>\n"
        }
        // Link: audio -> ch1
        xml += "            <link>\n"
        xml += "              <linkclipref>\(entry.audioClipItemCh1ID)</linkclipref>\n"
        xml += "              <mediatype>audio</mediatype>\n"
        xml += "              <trackindex>\(entry.audioTrackCh1Index)</trackindex>\n"
        xml += "              <clipindex>1</clipindex>\n"
        xml += "              <groupindex>1</groupindex>\n"
        xml += "            </link>\n"
        // Link: audio -> ch2
        xml += "            <link>\n"
        xml += "              <linkclipref>\(entry.audioClipItemCh2ID)</linkclipref>\n"
        xml += "              <mediatype>audio</mediatype>\n"
        xml += "              <trackindex>\(entry.audioTrackCh2Index)</trackindex>\n"
        xml += "              <clipindex>1</clipindex>\n"
        xml += "              <groupindex>2</groupindex>\n"
        xml += "            </link>\n"
        xml += "          </clipitem>\n"
        xml += "          <enabled>TRUE</enabled>\n"
        xml += "          <locked>FALSE</locked>\n"
        xml += "          <outputchannelindex>\(outputChannelIndex)</outputchannelindex>\n"
        xml += "        </track>\n\n"
        return xml
    }

    private func buildFileElementFull(entry: TrackEntry, frameRate: Int, ntsc: String) -> String {
        let rawPath = entry.clip.url.path
        let encodedPath = rawPath.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? rawPath
        let pathURL = "file://localhost" + encodedPath
        let name = escapeXML(entry.clip.filename)
        let dur = entry.durationFrames

        var xml = "<file id=\"\(entry.fileID)\">"
        xml += "<name>\(name)</name>"
        xml += "<pathurl>\(pathURL)</pathurl>"
        xml += "<rate><timebase>\(frameRate)</timebase><ntsc>\(ntsc)</ntsc></rate>"
        xml += "<duration>\(dur)</duration>"
        xml += "<timecode>"
        xml += "<rate><timebase>\(frameRate)</timebase><ntsc>\(ntsc)</ntsc></rate>"
        xml += "<string>00:00:00:00</string><frame>0</frame><displayformat>NDF</displayformat>"
        xml += "</timecode>"
        xml += "<media>"
        if entry.clip.isVideo {
            xml += "<video><samplecharacteristics>"
            xml += "<rate><timebase>\(frameRate)</timebase><ntsc>\(ntsc)</ntsc></rate>"
            xml += "<width>1920</width><height>1080</height>"
            xml += "<anamorphic>FALSE</anamorphic><pixelaspectratio>square</pixelaspectratio>"
            xml += "<fielddominance>none</fielddominance>"
            xml += "</samplecharacteristics></video>"
        }
        xml += "<audio><samplecharacteristics>"
        xml += "<depth>16</depth><samplerate>48000</samplerate>"
        xml += "</samplecharacteristics><channelcount>2</channelcount></audio>"
        xml += "</media>"
        xml += "</file>"
        return xml
    }

    private func buildAudioOutputs(entries: [TrackEntry]) -> String {
        var xml = ""
        for entry in entries {
            xml += "          <group>\n"
            xml += "            <index>\(entry.audioTrackCh1Index)</index>\n"
            xml += "            <numchannels>2</numchannels>\n"
            xml += "            <downmix>0</downmix>\n"
            xml += "            <channel><index>\(entry.audioTrackCh1Index)</index></channel>\n"
            xml += "            <channel><index>\(entry.audioTrackCh2Index)</index></channel>\n"
            xml += "          </group>\n"
        }
        return xml
    }

    private func buildSequenceXML(frameRate: Int, ntsc: String, totalDurationFrames: Int, videoTracksXML: String, audioTracksXML: String, outputsXML: String) -> String {
        var xml = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
        xml += "<!DOCTYPE xmeml>\n"
        xml += "<xmeml version=\"4\">\n"
        xml += "  <sequence id=\"sequence-1\">\n"
        xml += "    <uuid>\(UUID().uuidString)</uuid>\n"
        xml += "    <name>SyncWave Export</name>\n"
        xml += "    <duration>\(totalDurationFrames)</duration>\n"
        xml += "    <rate>\n"
        xml += "      <timebase>\(frameRate)</timebase>\n"
        xml += "      <ntsc>\(ntsc)</ntsc>\n"
        xml += "    </rate>\n"
        xml += "    <timecode>\n"
        xml += "      <rate>\n"
        xml += "        <timebase>\(frameRate)</timebase>\n"
        xml += "        <ntsc>\(ntsc)</ntsc>\n"
        xml += "      </rate>\n"
        xml += "      <string>00:00:00:00</string>\n"
        xml += "      <frame>0</frame>\n"
        xml += "      <displayformat>NDF</displayformat>\n"
        xml += "    </timecode>\n"
        xml += "    <media>\n"
        xml += "      <video>\n"
        xml += "        <format>\n"
        xml += "          <samplecharacteristics>\n"
        xml += "            <rate>\n"
        xml += "              <timebase>\(frameRate)</timebase>\n"
        xml += "              <ntsc>\(ntsc)</ntsc>\n"
        xml += "            </rate>\n"
        xml += "            <width>1920</width>\n"
        xml += "            <height>1080</height>\n"
        xml += "            <anamorphic>FALSE</anamorphic>\n"
        xml += "            <pixelaspectratio>square</pixelaspectratio>\n"
        xml += "            <fielddominance>none</fielddominance>\n"
        xml += "            <colordepth>24</colordepth>\n"
        xml += "          </samplecharacteristics>\n"
        xml += "        </format>\n"
        xml += videoTracksXML
        xml += "      </video>\n"
        xml += "      <audio>\n"
        xml += "        <numOutputChannels>2</numOutputChannels>\n"
        xml += "        <format>\n"
        xml += "          <samplecharacteristics>\n"
        xml += "            <depth>16</depth>\n"
        xml += "            <samplerate>48000</samplerate>\n"
        xml += "          </samplecharacteristics>\n"
        xml += "        </format>\n"
        xml += "        <outputs>\n"
        xml += outputsXML
        xml += "        </outputs>\n"
        xml += audioTracksXML
        xml += "      </audio>\n"
        xml += "    </media>\n"
        xml += "  </sequence>\n"
        xml += "</xmeml>\n"
        return xml
    }

    private func escapeXML(_ string: String) -> String {
        string.replacingOccurrences(of: "&", with: "&amp;")
              .replacingOccurrences(of: "<", with: "&lt;")
              .replacingOccurrences(of: ">", with: "&gt;")
              .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
