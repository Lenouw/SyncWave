// Tests/SyncWaveTests/Engine/ExportEngineTests.swift
import XCTest
@testable import SyncWave

final class ExportEngineTests: XCTestCase {

    func testGeneratesValidFCP7XML() throws {
        var camA = MediaClip(url: URL(fileURLWithPath: "/media/CamA.MOV"), filename: "CamA.MOV",
                   duration: 3600, hasAudioTrack: true, audioSampleRate: 48000, isVideo: true)
        camA.offset = 0
        var camB = MediaClip(url: URL(fileURLWithPath: "/media/CamB.MOV"), filename: "CamB.MOV",
                   duration: 3500, hasAudioTrack: true, audioSampleRate: 48000, isVideo: true)
        camB.offset = 2.5
        var audio = MediaClip(url: URL(fileURLWithPath: "/media/Audio.WAV"), filename: "Audio.WAV",
                   duration: 3600, hasAudioTrack: true, audioSampleRate: 48000, isVideo: false)
        audio.offset = 0.8

        let tracks = [
            Track(name: "V1", type: .video, clips: [camA]),
            Track(name: "V2", type: .video, clips: [camB]),
            Track(name: "A1", type: .audio, clips: [audio]),
        ]

        let engine = ExportEngine()
        let xml = try engine.generateTrackBasedXML(
            tracks: tracks, syncedClips: [camA, camB, audio],
            settings: ExportSettings(), frameRate: 25
        )

        XCTAssertTrue(xml.contains("<?xml version=\"1.0\""))
        XCTAssertTrue(xml.contains("<xmeml version=\"4\">"))
        XCTAssertTrue(xml.contains("<name>SyncWave Export</name>"))
        XCTAssertTrue(xml.contains("<timebase>25</timebase>"))
        XCTAssertTrue(xml.contains("CamA.MOV"))
        XCTAssertTrue(xml.contains("CamB.MOV"))
        XCTAssertTrue(xml.contains("Audio.WAV"))

        let xmlDoc = try XMLDocument(xmlString: xml)
        XCTAssertNotNil(xmlDoc.rootElement())
    }

    func testMultipleClipsPerTrack() throws {
        var cam1a = MediaClip(url: URL(fileURLWithPath: "/media/Cam1_001.MOV"), filename: "Cam1_001.MOV",
                   duration: 600, hasAudioTrack: true, audioSampleRate: 48000, isVideo: true)
        cam1a.offset = 0
        var cam1b = MediaClip(url: URL(fileURLWithPath: "/media/Cam1_002.MOV"), filename: "Cam1_002.MOV",
                   duration: 600, hasAudioTrack: true, audioSampleRate: 48000, isVideo: true)
        cam1b.offset = 700  // 100s gap between clips

        let tracks = [
            Track(name: "V1", type: .video, clips: [cam1a, cam1b]),
        ]

        let engine = ExportEngine()
        let xml = try engine.generateTrackBasedXML(
            tracks: tracks, syncedClips: [cam1a, cam1b],
            settings: ExportSettings(), frameRate: 30
        )

        // Both clips should be in the same video track
        XCTAssertTrue(xml.contains("Cam1_001.MOV"))
        XCTAssertTrue(xml.contains("Cam1_002.MOV"))

        let xmlDoc = try XMLDocument(xmlString: xml)
        XCTAssertNotNil(xmlDoc.rootElement())

        // Count video tracks — should be exactly 1
        let videoTracks = try xmlDoc.nodes(forXPath: "//video/track")
        XCTAssertEqual(videoTracks.count, 1, "Should have 1 video track, not \(videoTracks.count)")
    }
}
