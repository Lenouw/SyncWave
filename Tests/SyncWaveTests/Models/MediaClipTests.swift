import XCTest
@testable import SyncWave

final class MediaClipTests: XCTestCase {

    func testMediaClipInitialization() {
        let url = URL(fileURLWithPath: "/tmp/test.mov")
        let clip = MediaClip(
            url: url,
            filename: "test.mov",
            duration: 120.0,
            hasAudioTrack: true,
            audioSampleRate: 48000,
            isVideo: true
        )

        XCTAssertEqual(clip.filename, "test.mov")
        XCTAssertEqual(clip.duration, 120.0)
        XCTAssertEqual(clip.syncStatus, .pending)
        XCTAssertNil(clip.offset)
        XCTAssertNil(clip.driftPPM)
        XCTAssertNil(clip.confidence)
    }

    func testSyncStatusTransitions() {
        var clip = MediaClip(
            url: URL(fileURLWithPath: "/tmp/test.mov"),
            filename: "test.mov",
            duration: 60.0,
            hasAudioTrack: true,
            audioSampleRate: 48000,
            isVideo: true
        )

        XCTAssertEqual(clip.syncStatus, .pending)

        clip.applySyncResult(offset: 2.5, driftPPM: 12.0, confidence: 0.85)
        XCTAssertEqual(clip.syncStatus, .synced)
        XCTAssertEqual(clip.offset, 2.5)

        clip.applySyncResult(offset: 1.0, driftPPM: 5.0, confidence: 0.5)
        XCTAssertEqual(clip.syncStatus, .lowConfidence)

        clip.applySyncResult(offset: 0.0, driftPPM: 0.0, confidence: 0.1)
        XCTAssertEqual(clip.syncStatus, .failed)
    }

    func testClipWithoutAudioCannotSync() {
        let clip = MediaClip(
            url: URL(fileURLWithPath: "/tmp/video_no_audio.mov"),
            filename: "video_no_audio.mov",
            duration: 60.0,
            hasAudioTrack: false,
            audioSampleRate: 0,
            isVideo: true
        )
        XCTAssertFalse(clip.canSync)
    }
}
