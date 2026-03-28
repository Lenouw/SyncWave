// Tests/SyncWaveTests/Engine/ExportEngineTests.swift
import XCTest
@testable import SyncWave

final class ExportEngineTests: XCTestCase {

    func testGeneratesValidFCP7XML() throws {
        let clips = [
            MediaClip(url: URL(fileURLWithPath: "/media/CamA.MOV"), filename: "CamA.MOV",
                       duration: 3600, hasAudioTrack: true, audioSampleRate: 48000, isVideo: true),
            MediaClip(url: URL(fileURLWithPath: "/media/CamB.MOV"), filename: "CamB.MOV",
                       duration: 3500, hasAudioTrack: true, audioSampleRate: 48000, isVideo: true),
            MediaClip(url: URL(fileURLWithPath: "/media/Audio.WAV"), filename: "Audio.WAV",
                       duration: 3600, hasAudioTrack: true, audioSampleRate: 48000, isVideo: false),
        ]

        let syncResult = SyncResult(
            referenceClipID: clips[0].id,
            alignments: [
                ClipAlignment(clipID: clips[1].id, offset: 2.5, driftPPM: 12, confidence: 0.9),
                ClipAlignment(clipID: clips[2].id, offset: 0.8, driftPPM: 3, confidence: 0.95),
            ],
            processingTime: 1.5
        )

        let engine = ExportEngine()
        let xml = try engine.generateFCP7XML(clips: clips, syncResult: syncResult, settings: ExportSettings(), frameRate: 25)

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

    func testExcludesUnsyncedClipsWhenConfigured() throws {
        var failedClip = MediaClip(url: URL(fileURLWithPath: "/media/Bad.MOV"), filename: "Bad.MOV",
            duration: 100, hasAudioTrack: true, audioSampleRate: 48000, isVideo: true)
        failedClip.syncStatus = .failed

        let refClip = MediaClip(url: URL(fileURLWithPath: "/media/CamA.MOV"), filename: "CamA.MOV",
            duration: 3600, hasAudioTrack: true, audioSampleRate: 48000, isVideo: true)

        let syncResult = SyncResult(
            referenceClipID: refClip.id,
            alignments: [ClipAlignment(clipID: failedClip.id, offset: 0, driftPPM: 0, confidence: 0.1)],
            processingTime: 0.5
        )

        var settings = ExportSettings()
        settings.includeUnsyncedClips = false

        let engine = ExportEngine()
        let xml = try engine.generateFCP7XML(clips: [refClip, failedClip], syncResult: syncResult, settings: settings, frameRate: 25)

        XCTAssertTrue(xml.contains("CamA.MOV"))
        XCTAssertFalse(xml.contains("Bad.MOV"))
    }
}
