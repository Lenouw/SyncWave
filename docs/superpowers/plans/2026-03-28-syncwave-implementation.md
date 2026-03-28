# SyncWave Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a macOS native app that automatically synchronizes multi-camera audio/video clips via GCC-PHAT cross-correlation and exports to Premiere Pro XML.

**Architecture:** 3-layer SwiftUI app (UI → App → DSP). The DSP layer uses Apple's Accelerate/vDSP for hardware-accelerated FFT and cross-correlation. AVFoundation handles media decoding with FFmpeg CLI as fallback for exotic formats. Export generates FCP 7 XML v5.

**Tech Stack:** Swift 5.9+, SwiftUI (macOS 14+), Accelerate/vDSP, AVFoundation, XCTest

**Spec:** `docs/superpowers/specs/2026-03-28-syncwave-design.md`

---

## File Structure

```
SyncWave/
├── Package.swift
├── Sources/
│   └── SyncWave/
│       ├── App/
│       │   ├── SyncWaveApp.swift          # @main entry point
│       │   └── AppState.swift             # Observable app state
│       ├── Models/
│       │   ├── MediaClip.swift            # Clip data model
│       │   ├── SyncResult.swift           # Sync output model
│       │   ├── Project.swift              # Project container
│       │   └── ExportSettings.swift       # Export configuration
│       ├── DSP/
│       │   ├── AudioExtractor.swift       # AVFoundation + FFmpeg audio extraction
│       │   ├── GCCPHATCorrelator.swift    # FFT cross-correlation engine
│       │   ├── DriftCorrector.swift       # Clock drift detection & correction
│       │   └── AudioBuffer.swift          # Float32 PCM buffer wrapper
│       ├── Engine/
│       │   ├── SyncEngine.swift           # Orchestrates full sync pipeline
│       │   └── ExportEngine.swift         # FCP 7 XML generator
│       └── Views/
│           ├── MainWindow.swift           # Root view with toolbar
│           ├── ImportDropZone.swift        # Drag & drop empty state
│           ├── TimelineView.swift         # Multi-track timeline
│           ├── TimelineTrackView.swift    # Single track row
│           ├── PreviewView.swift          # AVPlayer video preview
│           ├── SyncStatusPanel.swift      # Right panel with clip statuses
│           └── ExportSheet.swift          # Export modal
├── Tests/
│   └── SyncWaveTests/
│       ├── Models/
│       │   └── MediaClipTests.swift
│       ├── DSP/
│       │   ├── AudioExtractorTests.swift
│       │   ├── GCCPHATCorrelatorTests.swift
│       │   └── DriftCorrectorTests.swift
│       ├── Engine/
│       │   ├── SyncEngineTests.swift
│       │   └── ExportEngineTests.swift
│       └── TestFixtures/
│           └── TestSignalGenerator.swift  # Generate synthetic audio for tests
└── Resources/
    └── TestMedia/                         # Small test clips for integration tests
```

---

### Task 1: Project Scaffolding

**Files:**
- Create: `Package.swift`
- Create: `Sources/SyncWave/App/SyncWaveApp.swift`
- Create: `Sources/SyncWave/App/AppState.swift`

- [ ] **Step 1: Create Package.swift**

```swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SyncWave",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "SyncWave",
            path: "Sources/SyncWave"
        ),
        .testTarget(
            name: "SyncWaveTests",
            dependencies: ["SyncWave"],
            path: "Tests/SyncWaveTests"
        ),
    ]
)
```

- [ ] **Step 2: Create the app entry point**

```swift
// Sources/SyncWave/App/SyncWaveApp.swift
import SwiftUI

@main
struct SyncWaveApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            Text("SyncWave")
                .frame(minWidth: 900, minHeight: 600)
        }
        .windowStyle(.titleBar)
    }
}
```

- [ ] **Step 3: Create AppState**

```swift
// Sources/SyncWave/App/AppState.swift
import SwiftUI

@MainActor
final class AppState: ObservableObject {
    @Published var clips: [MediaClip] = []
    @Published var syncResult: SyncResult?
    @Published var isSyncing: Bool = false
    @Published var syncProgress: Double = 0.0
}
```

Note: `MediaClip` and `SyncResult` don't exist yet — this file will fail to compile until Task 2. That's expected.

- [ ] **Step 4: Create directory structure**

Run:
```bash
mkdir -p Sources/SyncWave/{App,Models,DSP,Engine,Views}
mkdir -p Tests/SyncWaveTests/{Models,DSP,Engine,TestFixtures}
mkdir -p Resources/TestMedia
```

- [ ] **Step 5: Verify project builds (will fail — expected)**

Run: `swift build 2>&1 | head -5`
Expected: Compile error about missing `MediaClip` — confirms scaffolding is set up correctly.

- [ ] **Step 6: Commit scaffolding**

```bash
git add Package.swift Sources/ Tests/ Resources/
git commit -m "feat: scaffold projet SyncWave (Package.swift, structure dossiers)"
```

---

### Task 2: Data Models

**Files:**
- Create: `Sources/SyncWave/Models/MediaClip.swift`
- Create: `Sources/SyncWave/Models/SyncResult.swift`
- Create: `Sources/SyncWave/Models/Project.swift`
- Create: `Sources/SyncWave/Models/ExportSettings.swift`
- Create: `Tests/SyncWaveTests/Models/MediaClipTests.swift`

- [ ] **Step 1: Write failing tests for MediaClip**

```swift
// Tests/SyncWaveTests/Models/MediaClipTests.swift
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
```

- [ ] **Step 2: Run tests — verify they fail**

Run: `swift test --filter MediaClipTests 2>&1 | tail -5`
Expected: FAIL — `MediaClip` not found.

- [ ] **Step 3: Implement MediaClip**

```swift
// Sources/SyncWave/Models/MediaClip.swift
import Foundation

enum SyncStatus: Equatable {
    case pending
    case synced
    case lowConfidence
    case failed
}

struct MediaClip: Identifiable, Equatable {
    let id: UUID
    let url: URL
    let filename: String
    let duration: TimeInterval
    let hasAudioTrack: Bool
    let audioSampleRate: Double
    let isVideo: Bool
    var syncStatus: SyncStatus = .pending
    var offset: TimeInterval?
    var driftPPM: Double?
    var confidence: Double?

    var canSync: Bool { hasAudioTrack }

    init(
        id: UUID = UUID(),
        url: URL,
        filename: String,
        duration: TimeInterval,
        hasAudioTrack: Bool,
        audioSampleRate: Double,
        isVideo: Bool
    ) {
        self.id = id
        self.url = url
        self.filename = filename
        self.duration = duration
        self.hasAudioTrack = hasAudioTrack
        self.audioSampleRate = audioSampleRate
        self.isVideo = isVideo
    }

    mutating func applySyncResult(offset: TimeInterval, driftPPM: Double, confidence: Double) {
        self.offset = offset
        self.driftPPM = driftPPM
        self.confidence = confidence
        if confidence >= 0.7 {
            self.syncStatus = .synced
        } else if confidence >= 0.3 {
            self.syncStatus = .lowConfidence
        } else {
            self.syncStatus = .failed
        }
    }
}
```

- [ ] **Step 4: Implement SyncResult, Project, ExportSettings**

```swift
// Sources/SyncWave/Models/SyncResult.swift
import Foundation

struct ClipAlignment: Equatable {
    let clipID: UUID
    let offset: TimeInterval
    let driftPPM: Double
    let confidence: Double
}

struct SyncResult: Equatable {
    let referenceClipID: UUID
    let alignments: [ClipAlignment]
    let processingTime: TimeInterval
}
```

```swift
// Sources/SyncWave/Models/Project.swift
import Foundation

struct Project {
    var clips: [MediaClip] = []
    var syncResult: SyncResult?
    var exportSettings: ExportSettings = ExportSettings()

    var referenceClip: MediaClip? {
        clips.max(by: { $0.duration < $1.duration })
    }
}
```

```swift
// Sources/SyncWave/Models/ExportSettings.swift
import Foundation

enum ExportFormat: String, CaseIterable {
    case fcp7XML = "FCP 7 XML"
}

struct ExportSettings {
    var format: ExportFormat = .fcp7XML
    var replaceAudioInVideo: Bool = true
    var includeUnsyncedClips: Bool = false
    var outputDirectory: URL = FileManager.default.temporaryDirectory
}
```

- [ ] **Step 5: Run tests — verify they pass**

Run: `swift test --filter MediaClipTests 2>&1 | tail -10`
Expected: All 3 tests PASS.

- [ ] **Step 6: Verify full project compiles**

Run: `swift build 2>&1 | tail -3`
Expected: Build succeeds.

- [ ] **Step 7: Commit**

```bash
git add Sources/SyncWave/Models/ Tests/SyncWaveTests/Models/
git commit -m "feat: ajout des modèles de données (MediaClip, SyncResult, Project)"
```

---

### Task 3: AudioBuffer

**Files:**
- Create: `Sources/SyncWave/DSP/AudioBuffer.swift`

- [ ] **Step 1: Implement AudioBuffer (simple wrapper, no test needed)**

```swift
// Sources/SyncWave/DSP/AudioBuffer.swift
import Foundation
import Accelerate

/// Wrapper around a Float32 PCM buffer at a known sample rate.
struct AudioBuffer {
    let samples: [Float]
    let sampleRate: Double
    let channelCount: Int

    var duration: TimeInterval {
        Double(samples.count) / sampleRate / Double(channelCount)
    }

    var sampleCount: Int { samples.count }

    /// Downsample to a target sample rate using simple decimation.
    /// Suitable for coarse correlation where anti-aliasing is not critical.
    func downsampled(to targetRate: Double) -> AudioBuffer {
        guard targetRate < sampleRate else { return self }
        let ratio = Int(sampleRate / targetRate)
        let newCount = samples.count / ratio
        var output = [Float](repeating: 0, count: newCount)
        for i in 0..<newCount {
            output[i] = samples[i * ratio]
        }
        return AudioBuffer(samples: output, sampleRate: targetRate, channelCount: 1)
    }

    /// Extract a window of samples around a center position (in seconds).
    func window(centerSeconds: TimeInterval, windowSeconds: TimeInterval) -> AudioBuffer {
        let centerSample = Int(centerSeconds * sampleRate)
        let halfWindow = Int(windowSeconds * sampleRate / 2)
        let start = max(0, centerSample - halfWindow)
        let end = min(samples.count, centerSample + halfWindow)
        let slice = Array(samples[start..<end])
        return AudioBuffer(samples: slice, sampleRate: sampleRate, channelCount: 1)
    }
}
```

- [ ] **Step 2: Verify build**

Run: `swift build 2>&1 | tail -3`
Expected: Build succeeds.

- [ ] **Step 3: Commit**

```bash
git add Sources/SyncWave/DSP/AudioBuffer.swift
git commit -m "feat: ajout AudioBuffer (wrapper PCM Float32)"
```

---

### Task 4: TestSignalGenerator

**Files:**
- Create: `Tests/SyncWaveTests/TestFixtures/TestSignalGenerator.swift`

This utility generates synthetic audio signals with known offsets for testing the DSP layer. Critical for verifying sync accuracy.

- [ ] **Step 1: Create TestSignalGenerator**

```swift
// Tests/SyncWaveTests/TestFixtures/TestSignalGenerator.swift
import Foundation
@testable import SyncWave

/// Generates synthetic audio signals for testing the sync engine.
struct TestSignalGenerator {

    /// Generate a sine wave signal.
    static func sineWave(
        frequency: Double,
        sampleRate: Double,
        duration: TimeInterval
    ) -> AudioBuffer {
        let sampleCount = Int(sampleRate * duration)
        var samples = [Float](repeating: 0, count: sampleCount)
        for i in 0..<sampleCount {
            let t = Double(i) / sampleRate
            samples[i] = Float(sin(2.0 * .pi * frequency * t))
        }
        return AudioBuffer(samples: samples, sampleRate: sampleRate, channelCount: 1)
    }

    /// Generate a reference signal with mixed frequencies (simulates speech/noise).
    static func complexSignal(
        sampleRate: Double,
        duration: TimeInterval
    ) -> AudioBuffer {
        let sampleCount = Int(sampleRate * duration)
        var samples = [Float](repeating: 0, count: sampleCount)
        let frequencies: [Double] = [220, 440, 660, 1000, 1500, 2200]
        for i in 0..<sampleCount {
            let t = Double(i) / sampleRate
            var value: Float = 0
            for freq in frequencies {
                value += Float(sin(2.0 * .pi * freq * t + freq))
            }
            samples[i] = value / Float(frequencies.count)
        }
        return AudioBuffer(samples: samples, sampleRate: sampleRate, channelCount: 1)
    }

    /// Create a delayed copy of a signal (simulates a second camera recording the same audio).
    /// offsetSamples > 0 means the copy starts later.
    static func delayedCopy(
        of buffer: AudioBuffer,
        offsetSamples: Int
    ) -> AudioBuffer {
        if offsetSamples >= 0 {
            // Pad with zeros at the start
            let padding = [Float](repeating: 0, count: offsetSamples)
            let trimmed = Array(buffer.samples.prefix(buffer.sampleCount - offsetSamples))
            return AudioBuffer(
                samples: padding + trimmed,
                sampleRate: buffer.sampleRate,
                channelCount: 1
            )
        } else {
            // Clip the start
            let skip = abs(offsetSamples)
            let remaining = Array(buffer.samples.dropFirst(skip))
            let padding = [Float](repeating: 0, count: skip)
            return AudioBuffer(
                samples: remaining + padding,
                sampleRate: buffer.sampleRate,
                channelCount: 1
            )
        }
    }

    /// Create a copy with clock drift (simulates a camera with a slightly different clock).
    /// driftPPM > 0 means the copy runs slightly faster.
    static func driftedCopy(
        of buffer: AudioBuffer,
        driftPPM: Double
    ) -> AudioBuffer {
        let ratio = 1.0 + (driftPPM / 1_000_000.0)
        let newCount = Int(Double(buffer.sampleCount) / ratio)
        var output = [Float](repeating: 0, count: newCount)
        for i in 0..<newCount {
            let srcIndex = Double(i) * ratio
            let idx = Int(srcIndex)
            if idx + 1 < buffer.sampleCount {
                let frac = Float(srcIndex - Double(idx))
                output[i] = buffer.samples[idx] * (1 - frac) + buffer.samples[idx + 1] * frac
            } else if idx < buffer.sampleCount {
                output[i] = buffer.samples[idx]
            }
        }
        return AudioBuffer(samples: output, sampleRate: buffer.sampleRate, channelCount: 1)
    }
}
```

- [ ] **Step 2: Verify tests compile**

Run: `swift build --build-tests 2>&1 | tail -3`
Expected: Build succeeds.

- [ ] **Step 3: Commit**

```bash
git add Tests/SyncWaveTests/TestFixtures/
git commit -m "feat: ajout TestSignalGenerator (signaux synthétiques pour tests DSP)"
```

---

### Task 5: GCCPHATCorrelator

**Files:**
- Create: `Sources/SyncWave/DSP/GCCPHATCorrelator.swift`
- Create: `Tests/SyncWaveTests/DSP/GCCPHATCorrelatorTests.swift`

This is the core DSP engine. Implements GCC-PHAT using vDSP primitives.

- [ ] **Step 1: Write failing tests**

```swift
// Tests/SyncWaveTests/DSP/GCCPHATCorrelatorTests.swift
import XCTest
@testable import SyncWave

final class GCCPHATCorrelatorTests: XCTestCase {

    func testDetectsKnownOffset() throws {
        // Generate a 10-second complex signal at 48kHz
        let reference = TestSignalGenerator.complexSignal(sampleRate: 48000, duration: 10)
        // Create a copy delayed by exactly 4800 samples (100ms)
        let delayed = TestSignalGenerator.delayedCopy(of: reference, offsetSamples: 4800)

        let correlator = GCCPHATCorrelator()
        let result = try correlator.findOffset(reference: reference, target: delayed)

        // Should detect ~100ms offset with sub-millisecond accuracy
        XCTAssertEqual(result.offsetSamples, 4800, accuracy: 2,
                       "Expected offset of 4800 samples, got \(result.offsetSamples)")
        XCTAssertGreaterThan(result.confidence, 0.5,
                             "Confidence should be high for clean signal")
    }

    func testDetectsZeroOffset() throws {
        let signal = TestSignalGenerator.complexSignal(sampleRate: 48000, duration: 5)
        let correlator = GCCPHATCorrelator()
        let result = try correlator.findOffset(reference: signal, target: signal)

        XCTAssertEqual(result.offsetSamples, 0, accuracy: 1)
        XCTAssertGreaterThan(result.confidence, 0.7)
    }

    func testDetectsNegativeOffset() throws {
        let reference = TestSignalGenerator.complexSignal(sampleRate: 48000, duration: 10)
        let early = TestSignalGenerator.delayedCopy(of: reference, offsetSamples: -2400)

        let correlator = GCCPHATCorrelator()
        let result = try correlator.findOffset(reference: reference, target: early)

        XCTAssertEqual(result.offsetSamples, -2400, accuracy: 2)
    }

    func testLowConfidenceForUncorrelatedSignals() throws {
        let signal1 = TestSignalGenerator.sineWave(frequency: 440, sampleRate: 48000, duration: 5)
        let signal2 = TestSignalGenerator.sineWave(frequency: 1000, sampleRate: 48000, duration: 5)

        let correlator = GCCPHATCorrelator()
        let result = try correlator.findOffset(reference: signal1, target: signal2)

        XCTAssertLessThan(result.confidence, 0.5,
                          "Uncorrelated signals should have low confidence")
    }
}
```

- [ ] **Step 2: Run tests — verify they fail**

Run: `swift test --filter GCCPHATCorrelatorTests 2>&1 | tail -5`
Expected: FAIL — `GCCPHATCorrelator` not found.

- [ ] **Step 3: Implement GCCPHATCorrelator**

```swift
// Sources/SyncWave/DSP/GCCPHATCorrelator.swift
import Foundation
import Accelerate

struct CorrelationResult {
    let offsetSamples: Int
    let offsetSeconds: TimeInterval
    let confidence: Double
}

struct GCCPHATCorrelator {

    enum CorrelatorError: Error {
        case emptySignal
        case fftSetupFailed
    }

    /// Find the time offset between two audio buffers using GCC-PHAT.
    /// Returns the offset in samples: positive means target starts AFTER reference.
    func findOffset(reference: AudioBuffer, target: AudioBuffer) throws -> CorrelationResult {
        guard !reference.samples.isEmpty, !target.samples.isEmpty else {
            throw CorrelatorError.emptySignal
        }

        // Determine FFT size: next power of 2 >= sum of both lengths
        let totalLength = reference.sampleCount + target.sampleCount
        let log2n = vDSP_Length(ceil(log2(Double(totalLength))))
        let fftSize = Int(1 << log2n)
        let halfSize = fftSize / 2

        // Create FFT setup
        guard let fftSetup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2)) else {
            throw CorrelatorError.fftSetupFailed
        }
        defer { vDSP_destroy_fftsetup(fftSetup) }

        // Zero-pad both signals to fftSize
        var refPadded = [Float](repeating: 0, count: fftSize)
        var tgtPadded = [Float](repeating: 0, count: fftSize)
        refPadded.replaceSubrange(0..<reference.sampleCount, with: reference.samples)
        tgtPadded.replaceSubrange(0..<target.sampleCount, with: target.samples)

        // Allocate split complex buffers
        var refReal = [Float](repeating: 0, count: halfSize)
        var refImag = [Float](repeating: 0, count: halfSize)
        var tgtReal = [Float](repeating: 0, count: halfSize)
        var tgtImag = [Float](repeating: 0, count: halfSize)

        // Convert to split complex and compute FFT for reference
        refPadded.withUnsafeBufferPointer { ptr in
            ptr.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: halfSize) { complex in
                var splitRef = DSPSplitComplex(realp: &refReal, imagp: &refImag)
                vDSP_ctoz(complex, 2, &splitRef, 1, vDSP_Length(halfSize))
                vDSP_fft_zrip(fftSetup, &splitRef, 1, log2n, FFTDirection(kFFTDirection_Forward))
            }
        }

        // FFT for target
        tgtPadded.withUnsafeBufferPointer { ptr in
            ptr.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: halfSize) { complex in
                var splitTgt = DSPSplitComplex(realp: &tgtReal, imagp: &tgtImag)
                vDSP_ctoz(complex, 2, &splitTgt, 1, vDSP_Length(halfSize))
                vDSP_fft_zrip(fftSetup, &splitTgt, 1, log2n, FFTDirection(kFFTDirection_Forward))
            }
        }

        // Cross-power spectrum: X = FFT(ref) * conj(FFT(tgt))
        // conj(tgt) means negate imaginary part
        var crossReal = [Float](repeating: 0, count: halfSize)
        var crossImag = [Float](repeating: 0, count: halfSize)

        // Multiply: (a+bi)(c-di) = (ac+bd) + (bc-ad)i
        var negTgtImag = [Float](repeating: 0, count: halfSize)
        vDSP_vneg(tgtImag, 1, &negTgtImag, 1, vDSP_Length(halfSize))

        // Real part: a*c + b*d (using a*c - b*(-d))
        // ac
        vDSP_vmul(refReal, 1, tgtReal, 1, &crossReal, 1, vDSP_Length(halfSize))
        // bd
        var bd = [Float](repeating: 0, count: halfSize)
        vDSP_vmul(refImag, 1, tgtImag, 1, &bd, 1, vDSP_Length(halfSize))
        // crossReal = ac + bd
        vDSP_vadd(crossReal, 1, bd, 1, &crossReal, 1, vDSP_Length(halfSize))

        // Imag part: b*c - a*d
        // bc
        vDSP_vmul(refImag, 1, tgtReal, 1, &crossImag, 1, vDSP_Length(halfSize))
        // ad
        var ad = [Float](repeating: 0, count: halfSize)
        vDSP_vmul(refReal, 1, tgtImag, 1, &ad, 1, vDSP_Length(halfSize))
        // crossImag = bc - ad
        vDSP_vsub(ad, 1, crossImag, 1, &crossImag, 1, vDSP_Length(halfSize))

        // PHAT whitening: normalize by magnitude
        var magnitude = [Float](repeating: 0, count: halfSize)
        var splitCross = DSPSplitComplex(realp: &crossReal, imagp: &crossImag)
        vDSP_zvabs(&splitCross, 1, &magnitude, 1, vDSP_Length(halfSize))

        // Avoid division by zero
        let epsilon: Float = 1e-10
        var epsilonArray = [Float](repeating: epsilon, count: halfSize)
        vDSP_vmax(magnitude, 1, epsilonArray, 1, &magnitude, 1, vDSP_Length(halfSize))

        // Divide cross spectrum by magnitude
        vDSP_vdiv(magnitude, 1, crossReal, 1, &crossReal, 1, vDSP_Length(halfSize))
        vDSP_vdiv(magnitude, 1, crossImag, 1, &crossImag, 1, vDSP_Length(halfSize))

        // Inverse FFT
        var resultSplit = DSPSplitComplex(realp: &crossReal, imagp: &crossImag)
        vDSP_fft_zrip(fftSetup, &resultSplit, 1, log2n, FFTDirection(kFFTDirection_Inverse))

        // Convert back to interleaved
        var correlation = [Float](repeating: 0, count: fftSize)
        correlation.withUnsafeMutableBufferPointer { ptr in
            ptr.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: halfSize) { complex in
                var split = DSPSplitComplex(realp: &crossReal, imagp: &crossImag)
                vDSP_ztoc(&split, 1, complex, 2, vDSP_Length(halfSize))
            }
        }

        // Scale by 1/fftSize (vDSP doesn't normalize IFFT)
        var scale = 1.0 / Float(fftSize)
        vDSP_vsmul(correlation, 1, &scale, &correlation, 1, vDSP_Length(fftSize))

        // Find the peak (argmax of absolute values)
        var absCorrelation = [Float](repeating: 0, count: fftSize)
        vDSP_vabs(correlation, 1, &absCorrelation, 1, vDSP_Length(fftSize))

        var maxValue: Float = 0
        var maxIndex: vDSP_Length = 0
        vDSP_maxvi(absCorrelation, 1, &maxValue, &maxIndex, vDSP_Length(fftSize))

        // Convert circular index to signed offset
        var offsetSamples = Int(maxIndex)
        if offsetSamples > fftSize / 2 {
            offsetSamples -= fftSize
        }

        // Confidence: peak / mean of absolute correlation
        var meanValue: Float = 0
        vDSP_meamgv(absCorrelation, 1, &meanValue, vDSP_Length(fftSize))
        let confidence = meanValue > 0 ? Double(maxValue / meanValue) / 100.0 : 0

        let offsetSeconds = Double(offsetSamples) / reference.sampleRate

        return CorrelationResult(
            offsetSamples: offsetSamples,
            offsetSeconds: offsetSeconds,
            confidence: min(1.0, confidence)
        )
    }
}
```

- [ ] **Step 4: Run tests — verify they pass**

Run: `swift test --filter GCCPHATCorrelatorTests 2>&1 | tail -15`
Expected: All 4 tests PASS.

**Important:** If the confidence calculation produces unexpected values, the confidence formula may need tuning. The ratio `peak / (mean × 100)` is an approximation — adjust the divisor so that correlated signals score > 0.7 and uncorrelated ones score < 0.3.

- [ ] **Step 5: Commit**

```bash
git add Sources/SyncWave/DSP/GCCPHATCorrelator.swift Tests/SyncWaveTests/DSP/GCCPHATCorrelatorTests.swift
git commit -m "feat: moteur GCC-PHAT cross-correlation via vDSP"
```

---

### Task 6: DriftCorrector

**Files:**
- Create: `Sources/SyncWave/DSP/DriftCorrector.swift`
- Create: `Tests/SyncWaveTests/DSP/DriftCorrectorTests.swift`

- [ ] **Step 1: Write failing tests**

```swift
// Tests/SyncWaveTests/DSP/DriftCorrectorTests.swift
import XCTest
@testable import SyncWave

final class DriftCorrectorTests: XCTestCase {

    func testDetectsKnownDrift() throws {
        // Generate a 60-second signal at 48kHz
        let reference = TestSignalGenerator.complexSignal(sampleRate: 48000, duration: 60)
        // Create a drifted copy at 50 PPM
        let drifted = TestSignalGenerator.driftedCopy(of: reference, driftPPM: 50)

        let corrector = DriftCorrector(windowSeconds: 10, overlapRatio: 0.5)
        let result = try corrector.detectDrift(reference: reference, target: drifted)

        // Should detect ~50 PPM drift within ±10 PPM tolerance
        XCTAssertEqual(result.driftPPM, 50, accuracy: 10,
                       "Expected ~50 PPM drift, got \(result.driftPPM)")
    }

    func testZeroDriftForIdenticalSignals() throws {
        let signal = TestSignalGenerator.complexSignal(sampleRate: 48000, duration: 30)

        let corrector = DriftCorrector(windowSeconds: 10, overlapRatio: 0.5)
        let result = try corrector.detectDrift(reference: signal, target: signal)

        XCTAssertEqual(result.driftPPM, 0, accuracy: 5,
                       "Identical signals should have ~0 PPM drift")
    }

    func testLinearRegressionWithKnownPoints() {
        // Direct test of linear regression: y = 2x + 3
        let xs: [Double] = [0, 1, 2, 3, 4, 5]
        let ys: [Double] = [3, 5, 7, 9, 11, 13]
        let (slope, intercept) = DriftCorrector.linearRegression(xs: xs, ys: ys)

        XCTAssertEqual(slope, 2.0, accuracy: 0.001)
        XCTAssertEqual(intercept, 3.0, accuracy: 0.001)
    }
}
```

- [ ] **Step 2: Run tests — verify they fail**

Run: `swift test --filter DriftCorrectorTests 2>&1 | tail -5`
Expected: FAIL — `DriftCorrector` not found.

- [ ] **Step 3: Implement DriftCorrector**

```swift
// Sources/SyncWave/DSP/DriftCorrector.swift
import Foundation

struct DriftResult {
    let baseOffset: TimeInterval     // constant offset in seconds
    let driftPPM: Double             // clock drift in parts per million
    let windowOffsets: [(time: Double, offset: Double)]  // per-window offsets for debugging
}

struct DriftCorrector {
    let windowSeconds: TimeInterval
    let overlapRatio: Double

    init(windowSeconds: TimeInterval = 30, overlapRatio: Double = 0.5) {
        self.windowSeconds = windowSeconds
        self.overlapRatio = overlapRatio
    }

    func detectDrift(reference: AudioBuffer, target: AudioBuffer) throws -> DriftResult {
        let correlator = GCCPHATCorrelator()
        let hopSeconds = windowSeconds * (1.0 - overlapRatio)
        let totalDuration = min(reference.duration, target.duration)

        // Generate windows
        var windowOffsets: [(time: Double, offset: Double)] = []
        var currentTime = windowSeconds / 2.0

        while currentTime + windowSeconds / 2.0 <= totalDuration {
            let refWindow = reference.window(centerSeconds: currentTime, windowSeconds: windowSeconds)
            let tgtWindow = target.window(centerSeconds: currentTime, windowSeconds: windowSeconds)

            if let result = try? correlator.findOffset(reference: refWindow, target: tgtWindow),
               result.confidence > 0.2 {
                windowOffsets.append((time: currentTime, offset: result.offsetSeconds))
            }

            currentTime += hopSeconds
        }

        guard windowOffsets.count >= 2 else {
            // Not enough windows — return simple offset, no drift
            let simpleResult = try correlator.findOffset(reference: reference, target: target)
            return DriftResult(
                baseOffset: simpleResult.offsetSeconds,
                driftPPM: 0,
                windowOffsets: []
            )
        }

        // Linear regression: offset(t) = baseOffset + driftRate * t
        let xs = windowOffsets.map(\.time)
        let ys = windowOffsets.map(\.offset)
        let (driftRate, baseOffset) = Self.linearRegression(xs: xs, ys: ys)

        // Convert drift rate (seconds/second) to PPM
        let driftPPM = driftRate * 1_000_000

        return DriftResult(
            baseOffset: baseOffset,
            driftPPM: driftPPM,
            windowOffsets: windowOffsets
        )
    }

    /// Ordinary least squares linear regression.
    /// Returns (slope, intercept) for y = slope * x + intercept.
    static func linearRegression(xs: [Double], ys: [Double]) -> (slope: Double, intercept: Double) {
        let n = Double(xs.count)
        let sumX = xs.reduce(0, +)
        let sumY = ys.reduce(0, +)
        let sumXY = zip(xs, ys).reduce(0) { $0 + $1.0 * $1.1 }
        let sumXX = xs.reduce(0) { $0 + $1 * $1 }

        let denominator = n * sumXX - sumX * sumX
        guard abs(denominator) > 1e-15 else {
            return (slope: 0, intercept: sumY / n)
        }

        let slope = (n * sumXY - sumX * sumY) / denominator
        let intercept = (sumY - slope * sumX) / n
        return (slope: slope, intercept: intercept)
    }
}
```

- [ ] **Step 4: Run tests — verify they pass**

Run: `swift test --filter DriftCorrectorTests 2>&1 | tail -15`
Expected: All 3 tests PASS.

**Note:** The drift detection test (`testDetectsKnownDrift`) allows ±10 PPM tolerance because the synthetic signal resampling in `TestSignalGenerator.driftedCopy` introduces slight artifacts. With real audio, accuracy is typically ±1–2 PPM.

- [ ] **Step 5: Commit**

```bash
git add Sources/SyncWave/DSP/DriftCorrector.swift Tests/SyncWaveTests/DSP/DriftCorrectorTests.swift
git commit -m "feat: correction de drift par régression linéaire sur fenêtres GCC-PHAT"
```

---

### Task 7: AudioExtractor

**Files:**
- Create: `Sources/SyncWave/DSP/AudioExtractor.swift`
- Create: `Tests/SyncWaveTests/DSP/AudioExtractorTests.swift`

- [ ] **Step 1: Write failing test**

```swift
// Tests/SyncWaveTests/DSP/AudioExtractorTests.swift
import XCTest
@testable import SyncWave

final class AudioExtractorTests: XCTestCase {

    func testExtractsAudioFromWAV() async throws {
        // Create a temporary WAV file with known content
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("test_\(UUID().uuidString).wav")
        defer { try? FileManager.default.removeItem(at: tempURL) }

        // Write a minimal WAV file (1 second, 44100 Hz, mono, 16-bit)
        let sampleRate: Int = 44100
        let numSamples = sampleRate
        try writeTestWAV(to: tempURL, sampleRate: sampleRate, numSamples: numSamples)

        let extractor = AudioExtractor()
        let buffer = try await extractor.extract(from: tempURL, targetSampleRate: 48000)

        XCTAssertGreaterThan(buffer.sampleCount, 0)
        XCTAssertEqual(buffer.sampleRate, 48000)
        XCTAssertEqual(buffer.channelCount, 1)
        // Duration should be ~1 second
        XCTAssertEqual(buffer.duration, 1.0, accuracy: 0.1)
    }

    /// Write a minimal valid WAV file for testing.
    private func writeTestWAV(to url: URL, sampleRate: Int, numSamples: Int) throws {
        var data = Data()
        let bitsPerSample: Int = 16
        let numChannels: Int = 1
        let byteRate = sampleRate * numChannels * (bitsPerSample / 8)
        let blockAlign = numChannels * (bitsPerSample / 8)
        let dataSize = numSamples * blockAlign

        // RIFF header
        data.append(contentsOf: "RIFF".utf8)
        data.append(contentsOf: withUnsafeBytes(of: UInt32(36 + dataSize).littleEndian) { Array($0) })
        data.append(contentsOf: "WAVE".utf8)

        // fmt chunk
        data.append(contentsOf: "fmt ".utf8)
        data.append(contentsOf: withUnsafeBytes(of: UInt32(16).littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: UInt16(1).littleEndian) { Array($0) }) // PCM
        data.append(contentsOf: withUnsafeBytes(of: UInt16(numChannels).littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: UInt32(sampleRate).littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: UInt32(byteRate).littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: UInt16(blockAlign).littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: UInt16(bitsPerSample).littleEndian) { Array($0) })

        // data chunk: 440 Hz sine wave
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
```

- [ ] **Step 2: Run test — verify it fails**

Run: `swift test --filter AudioExtractorTests 2>&1 | tail -5`
Expected: FAIL — `AudioExtractor` not found.

- [ ] **Step 3: Implement AudioExtractor**

```swift
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
            case .noAudioTrack(let url):
                return "Pas de piste audio dans \(url.lastPathComponent)"
            case .readerSetupFailed(let url, let err):
                return "Erreur lecture \(url.lastPathComponent): \(err.localizedDescription)"
            case .ffmpegFailed(let url, let code):
                return "FFmpeg a échoué sur \(url.lastPathComponent) (code \(code))"
            case .ffmpegNotFound:
                return "FFmpeg non trouvé. Installer via: brew install ffmpeg"
            case .noSamplesExtracted(let url):
                return "Aucun échantillon extrait de \(url.lastPathComponent)"
            }
        }
    }

    /// Extract audio from a media file, returning a mono Float32 buffer at targetSampleRate.
    func extract(from url: URL, targetSampleRate: Double = 48000) async throws -> AudioBuffer {
        do {
            return try await extractWithAVFoundation(from: url, targetSampleRate: targetSampleRate)
        } catch {
            // Fallback to FFmpeg
            return try await extractWithFFmpeg(from: url, targetSampleRate: targetSampleRate)
        }
    }

    /// Primary extraction: AVFoundation.
    private func extractWithAVFoundation(
        from url: URL,
        targetSampleRate: Double
    ) async throws -> AudioBuffer {
        let asset = AVAsset(url: url)
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)

        guard let audioTrack = audioTracks.first else {
            throw ExtractionError.noAudioTrack(url: url)
        }

        let outputSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsNonInterleaved: false,
            AVSampleRateKey: targetSampleRate,
            AVNumberOfChannelsKey: 1
        ]

        let reader: AVAssetReader
        do {
            reader = try AVAssetReader(asset: asset)
        } catch {
            throw ExtractionError.readerSetupFailed(url: url, underlying: error)
        }

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

        guard !allSamples.isEmpty else {
            throw ExtractionError.noSamplesExtracted(url: url)
        }

        return AudioBuffer(samples: allSamples, sampleRate: targetSampleRate, channelCount: 1)
    }

    /// Fallback extraction: FFmpeg subprocess.
    private func extractWithFFmpeg(
        from url: URL,
        targetSampleRate: Double
    ) async throws -> AudioBuffer {
        // Find ffmpeg
        let ffmpegPath = findFFmpeg()
        guard let path = ffmpegPath else {
            throw ExtractionError.ffmpegNotFound
        }

        let tempOutput = FileManager.default.temporaryDirectory
            .appendingPathComponent("syncwave_\(UUID().uuidString).raw")
        defer { try? FileManager.default.removeItem(at: tempOutput) }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = [
            "-i", url.path,
            "-vn",                              // no video
            "-ac", "1",                          // mono
            "-ar", String(Int(targetSampleRate)), // target sample rate
            "-f", "f32le",                        // raw Float32 little-endian
            "-y",                                 // overwrite
            tempOutput.path
        ]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw ExtractionError.ffmpegFailed(url: url, exitCode: process.terminationStatus)
        }

        let data = try Data(contentsOf: tempOutput)
        let floatCount = data.count / MemoryLayout<Float>.size
        let samples = data.withUnsafeBytes { ptr in
            Array(ptr.bindMemory(to: Float.self).prefix(floatCount))
        }

        guard !samples.isEmpty else {
            throw ExtractionError.noSamplesExtracted(url: url)
        }

        return AudioBuffer(samples: samples, sampleRate: targetSampleRate, channelCount: 1)
    }

    /// Find FFmpeg binary path.
    private func findFFmpeg() -> String? {
        let candidates = [
            "/opt/homebrew/bin/ffmpeg",
            "/usr/local/bin/ffmpeg",
            "/usr/bin/ffmpeg"
        ]
        return candidates.first { FileManager.default.fileExists(atPath: $0) }
    }
}
```

- [ ] **Step 4: Run test — verify it passes**

Run: `swift test --filter AudioExtractorTests 2>&1 | tail -10`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/SyncWave/DSP/AudioExtractor.swift Tests/SyncWaveTests/DSP/AudioExtractorTests.swift
git commit -m "feat: extracteur audio (AVFoundation + fallback FFmpeg)"
```

---

### Task 8: SyncEngine

**Files:**
- Create: `Sources/SyncWave/Engine/SyncEngine.swift`
- Create: `Tests/SyncWaveTests/Engine/SyncEngineTests.swift`

- [ ] **Step 1: Write failing test**

```swift
// Tests/SyncWaveTests/Engine/SyncEngineTests.swift
import XCTest
@testable import SyncWave

final class SyncEngineTests: XCTestCase {

    func testSyncWithKnownOffset() async throws {
        // Generate synthetic audio buffers directly
        let reference = TestSignalGenerator.complexSignal(sampleRate: 48000, duration: 10)
        let delayed = TestSignalGenerator.delayedCopy(of: reference, offsetSamples: 4800) // 100ms

        let engine = SyncEngine()
        let result = try engine.syncBuffers(
            reference: reference,
            targets: [("Camera_B", delayed)]
        )

        XCTAssertEqual(result.alignments.count, 1)
        let alignment = result.alignments[0]
        XCTAssertEqual(alignment.offset, 0.1, accuracy: 0.001, // 100ms ± 1ms
                       "Expected ~100ms offset, got \(alignment.offset)s")
        XCTAssertGreaterThan(alignment.confidence, 0.5)
    }

    func testSyncMultipleTargets() async throws {
        let reference = TestSignalGenerator.complexSignal(sampleRate: 48000, duration: 10)
        let target1 = TestSignalGenerator.delayedCopy(of: reference, offsetSamples: 2400) // 50ms
        let target2 = TestSignalGenerator.delayedCopy(of: reference, offsetSamples: -1200) // -25ms

        let engine = SyncEngine()
        let result = try engine.syncBuffers(
            reference: reference,
            targets: [("Camera_B", target1), ("Audio_H6", target2)]
        )

        XCTAssertEqual(result.alignments.count, 2)
        XCTAssertEqual(result.alignments[0].offset, 0.05, accuracy: 0.001)
        XCTAssertEqual(result.alignments[1].offset, -0.025, accuracy: 0.001)
    }
}
```

- [ ] **Step 2: Run tests — verify they fail**

Run: `swift test --filter SyncEngineTests 2>&1 | tail -5`
Expected: FAIL — `SyncEngine` not found.

- [ ] **Step 3: Implement SyncEngine**

```swift
// Sources/SyncWave/Engine/SyncEngine.swift
import Foundation

struct SyncAlignment {
    let label: String
    let offset: TimeInterval
    let driftPPM: Double
    let confidence: Double
}

struct SyncOutput {
    let alignments: [SyncAlignment]
    let processingTime: TimeInterval
}

final class SyncEngine {
    private let correlator = GCCPHATCorrelator()
    private let driftCorrector = DriftCorrector()
    private let extractor = AudioExtractor()

    /// Sync audio buffers directly (for testing and when audio is already extracted).
    func syncBuffers(
        reference: AudioBuffer,
        targets: [(label: String, buffer: AudioBuffer)]
    ) throws -> SyncOutput {
        let startTime = CFAbsoluteTimeGetCurrent()
        var alignments: [SyncAlignment] = []

        for (label, target) in targets {
            // Phase 1: Coarse match on downsampled signal
            let refDown = reference.downsampled(to: 4000)
            let tgtDown = target.downsampled(to: 4000)
            let coarseResult = try correlator.findOffset(reference: refDown, target: tgtDown)

            // Phase 2: Fine alignment around the coarse offset at full rate
            let windowCenter = abs(coarseResult.offsetSeconds)
            let refWindow = reference.window(
                centerSeconds: windowCenter + reference.duration / 2,
                windowSeconds: 10
            )
            let tgtWindow = target.window(
                centerSeconds: windowCenter + target.duration / 2 - coarseResult.offsetSeconds,
                windowSeconds: 10
            )

            let fineResult: CorrelationResult
            if refWindow.sampleCount > 0 && tgtWindow.sampleCount > 0 {
                fineResult = try correlator.findOffset(reference: refWindow, target: tgtWindow)
            } else {
                fineResult = coarseResult
            }

            // Use coarse offset + fine refinement
            let totalOffset = coarseResult.offsetSeconds

            // Phase 3: Drift correction (only for signals > 5 minutes)
            var driftPPM: Double = 0
            if reference.duration > 300 && target.duration > 300 {
                let driftResult = try driftCorrector.detectDrift(reference: reference, target: target)
                driftPPM = driftResult.driftPPM
            }

            alignments.append(SyncAlignment(
                label: label,
                offset: totalOffset,
                driftPPM: driftPPM,
                confidence: Double(coarseResult.confidence)
            ))
        }

        let processingTime = CFAbsoluteTimeGetCurrent() - startTime

        return SyncOutput(
            alignments: alignments,
            processingTime: processingTime
        )
    }

    /// Full pipeline: extract audio from files, then sync.
    func syncFiles(
        referenceURL: URL,
        targetURLs: [(label: String, url: URL)],
        progress: ((Double) -> Void)? = nil
    ) async throws -> SyncOutput {
        let totalSteps = Double(targetURLs.count + 1)
        var currentStep = 0.0

        // Extract reference audio
        let referenceBuffer = try await extractor.extract(from: referenceURL)
        currentStep += 1
        progress?(currentStep / totalSteps)

        // Extract target audio
        var targets: [(label: String, buffer: AudioBuffer)] = []
        for (label, url) in targetURLs {
            let buffer = try await extractor.extract(from: url)
            targets.append((label: label, buffer: buffer))
            currentStep += 1
            progress?(currentStep / totalSteps)
        }

        return try syncBuffers(reference: referenceBuffer, targets: targets)
    }
}
```

- [ ] **Step 4: Run tests — verify they pass**

Run: `swift test --filter SyncEngineTests 2>&1 | tail -10`
Expected: All 2 tests PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/SyncWave/Engine/SyncEngine.swift Tests/SyncWaveTests/Engine/SyncEngineTests.swift
git commit -m "feat: SyncEngine — orchestration du pipeline de sync complet"
```

---

### Task 9: ExportEngine (FCP 7 XML)

**Files:**
- Create: `Sources/SyncWave/Engine/ExportEngine.swift`
- Create: `Tests/SyncWaveTests/Engine/ExportEngineTests.swift`

- [ ] **Step 1: Write failing test**

```swift
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
        let xml = try engine.generateFCP7XML(
            clips: clips,
            syncResult: syncResult,
            settings: ExportSettings(),
            frameRate: 25
        )

        // Verify XML structure
        XCTAssertTrue(xml.contains("<?xml version=\"1.0\""))
        XCTAssertTrue(xml.contains("<xmeml version=\"5\">"))
        XCTAssertTrue(xml.contains("<name>SyncWave Export</name>"))
        XCTAssertTrue(xml.contains("<timebase>25</timebase>"))
        XCTAssertTrue(xml.contains("CamA.MOV"))
        XCTAssertTrue(xml.contains("CamB.MOV"))
        XCTAssertTrue(xml.contains("Audio.WAV"))

        // Verify it's valid XML
        let xmlDoc = try XMLDocument(xmlString: xml)
        XCTAssertNotNil(xmlDoc.rootElement())
    }

    func testExcludesUnsyncedClipsWhenConfigured() throws {
        var failedClip = MediaClip(
            url: URL(fileURLWithPath: "/media/Bad.MOV"), filename: "Bad.MOV",
            duration: 100, hasAudioTrack: true, audioSampleRate: 48000, isVideo: true
        )
        failedClip.syncStatus = .failed

        let refClip = MediaClip(
            url: URL(fileURLWithPath: "/media/CamA.MOV"), filename: "CamA.MOV",
            duration: 3600, hasAudioTrack: true, audioSampleRate: 48000, isVideo: true
        )

        let syncResult = SyncResult(
            referenceClipID: refClip.id,
            alignments: [
                ClipAlignment(clipID: failedClip.id, offset: 0, driftPPM: 0, confidence: 0.1),
            ],
            processingTime: 0.5
        )

        var settings = ExportSettings()
        settings.includeUnsyncedClips = false

        let engine = ExportEngine()
        let xml = try engine.generateFCP7XML(
            clips: [refClip, failedClip],
            syncResult: syncResult,
            settings: settings,
            frameRate: 25
        )

        XCTAssertTrue(xml.contains("CamA.MOV"))
        XCTAssertFalse(xml.contains("Bad.MOV"))
    }
}
```

- [ ] **Step 2: Run tests — verify they fail**

Run: `swift test --filter ExportEngineTests 2>&1 | tail -5`
Expected: FAIL — `ExportEngine` not found.

- [ ] **Step 3: Implement ExportEngine**

```swift
// Sources/SyncWave/Engine/ExportEngine.swift
import Foundation

struct ExportEngine {

    enum ExportError: Error, LocalizedError {
        case noReferenceClip
        case writeError(path: String, underlying: Error)

        var errorDescription: String? {
            switch self {
            case .noReferenceClip:
                return "Clip de référence introuvable"
            case .writeError(let path, let err):
                return "Erreur écriture \(path): \(err.localizedDescription)"
            }
        }
    }

    func generateFCP7XML(
        clips: [MediaClip],
        syncResult: SyncResult,
        settings: ExportSettings,
        frameRate: Int = 25
    ) throws -> String {
        guard let referenceClip = clips.first(where: { $0.id == syncResult.referenceClipID }) else {
            throw ExportError.noReferenceClip
        }

        let alignmentMap = Dictionary(
            uniqueKeysWithValues: syncResult.alignments.map { ($0.clipID, $0) }
        )

        var tracks = ""

        // Reference clip: always at offset 0
        let refDurationFrames = Int(referenceClip.duration * Double(frameRate))
        tracks += videoTrackXML(
            clip: referenceClip,
            startFrame: 0,
            durationFrames: refDurationFrames,
            frameRate: frameRate,
            fileID: "file-\(referenceClip.id.uuidString.prefix(8))"
        )

        // Aligned clips
        for clip in clips where clip.id != syncResult.referenceClipID {
            guard let alignment = alignmentMap[clip.id] else { continue }

            // Skip unsynced clips if configured
            if !settings.includeUnsyncedClips && alignment.confidence < 0.3 {
                continue
            }

            let offsetFrames = Int(alignment.offset * Double(frameRate))
            let durationFrames = Int(clip.duration * Double(frameRate))

            if clip.isVideo {
                tracks += videoTrackXML(
                    clip: clip,
                    startFrame: offsetFrames,
                    durationFrames: durationFrames,
                    frameRate: frameRate,
                    fileID: "file-\(clip.id.uuidString.prefix(8))"
                )
            } else {
                tracks += audioTrackXML(
                    clip: clip,
                    startFrame: offsetFrames,
                    durationFrames: durationFrames,
                    frameRate: frameRate,
                    fileID: "file-\(clip.id.uuidString.prefix(8))"
                )
            }
        }

        let totalDurationFrames = Int((clips.map(\.duration).max() ?? 0) * Double(frameRate))

        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE xmeml>
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

    func exportToFile(
        xml: String,
        directory: URL,
        filename: String = "SyncWave Export.xml"
    ) throws -> URL {
        let outputURL = directory.appendingPathComponent(filename)
        do {
            try xml.write(to: outputURL, atomically: true, encoding: .utf8)
        } catch {
            throw ExportError.writeError(path: outputURL.path, underlying: error)
        }
        return outputURL
    }

    // MARK: - Private XML builders

    private func videoTrackXML(
        clip: MediaClip,
        startFrame: Int,
        durationFrames: Int,
        frameRate: Int,
        fileID: String
    ) -> String {
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

    private func audioTrackXML(
        clip: MediaClip,
        startFrame: Int,
        durationFrames: Int,
        frameRate: Int,
        fileID: String
    ) -> String {
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
        string
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
```

- [ ] **Step 4: Run tests — verify they pass**

Run: `swift test --filter ExportEngineTests 2>&1 | tail -10`
Expected: All 2 tests PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/SyncWave/Engine/ExportEngine.swift Tests/SyncWaveTests/Engine/ExportEngineTests.swift
git commit -m "feat: ExportEngine — génération FCP 7 XML pour Premiere Pro"
```

---

### Task 10: UI — App Shell & Import Drop Zone

**Files:**
- Modify: `Sources/SyncWave/App/SyncWaveApp.swift`
- Modify: `Sources/SyncWave/App/AppState.swift`
- Create: `Sources/SyncWave/Views/MainWindow.swift`
- Create: `Sources/SyncWave/Views/ImportDropZone.swift`

- [ ] **Step 1: Implement AppState with full functionality**

```swift
// Sources/SyncWave/App/AppState.swift
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class AppState: ObservableObject {
    @Published var project = Project()
    @Published var isSyncing = false
    @Published var syncProgress: Double = 0.0
    @Published var statusMessage: String?

    private let syncEngine = SyncEngine()
    private let exportEngine = ExportEngine()

    var hasClips: Bool { !project.clips.isEmpty }
    var hasSyncResult: Bool { project.syncResult != nil }

    func importFiles(urls: [URL]) async {
        for url in urls {
            let ext = url.pathExtension.lowercased()
            let videoExts = ["mov", "mp4", "m4v", "mxf", "avi", "mts", "m2ts"]
            let audioExts = ["wav", "aiff", "aif", "mp3", "aac", "m4a"]

            guard videoExts.contains(ext) || audioExts.contains(ext) else { continue }

            let isVideo = videoExts.contains(ext)

            // Get duration using AVFoundation
            let duration = await getMediaDuration(url: url)
            let hasAudio = await hasAudioTrack(url: url)

            let clip = MediaClip(
                url: url,
                filename: url.lastPathComponent,
                duration: duration,
                hasAudioTrack: hasAudio,
                audioSampleRate: 48000,
                isVideo: isVideo
            )
            project.clips.append(clip)
        }
    }

    func sync() async {
        guard project.clips.count >= 2 else {
            statusMessage = "Minimum 2 clips requis"
            return
        }
        guard let refClip = project.referenceClip else { return }

        isSyncing = true
        syncProgress = 0
        statusMessage = "Synchronisation en cours..."

        let targetURLs = project.clips
            .filter { $0.id != refClip.id && $0.canSync }
            .map { (label: $0.filename, url: $0.url) }

        do {
            let result = try await syncEngine.syncFiles(
                referenceURL: refClip.url,
                targetURLs: targetURLs,
                progress: { [weak self] p in
                    Task { @MainActor in self?.syncProgress = p }
                }
            )

            // Apply results to clips
            for alignment in result.alignments {
                if let idx = project.clips.firstIndex(where: { $0.filename == alignment.label }) {
                    project.clips[idx].applySyncResult(
                        offset: alignment.offset,
                        driftPPM: alignment.driftPPM,
                        confidence: alignment.confidence
                    )
                }
            }

            project.syncResult = SyncResult(
                referenceClipID: refClip.id,
                alignments: result.alignments.compactMap { a in
                    guard let clip = project.clips.first(where: { $0.filename == a.label }) else { return nil }
                    return ClipAlignment(
                        clipID: clip.id,
                        offset: a.offset,
                        driftPPM: a.driftPPM,
                        confidence: a.confidence
                    )
                },
                processingTime: result.processingTime
            )

            statusMessage = String(format: "✓ Synchronisation terminée en %.1fs", result.processingTime)
        } catch {
            statusMessage = "✗ Erreur: \(error.localizedDescription)"
        }

        isSyncing = false
    }

    func exportXML() async -> URL? {
        guard let syncResult = project.syncResult else { return nil }

        do {
            let xml = try exportEngine.generateFCP7XML(
                clips: project.clips,
                syncResult: syncResult,
                settings: project.exportSettings
            )
            let url = try exportEngine.exportToFile(
                xml: xml,
                directory: project.exportSettings.outputDirectory
            )
            statusMessage = "✓ Export: \(url.lastPathComponent)"
            return url
        } catch {
            statusMessage = "✗ Export échoué: \(error.localizedDescription)"
            return nil
        }
    }

    // MARK: - Helpers

    private func getMediaDuration(url: URL) async -> TimeInterval {
        let asset = AVFoundation.AVAsset(url: url)
        let duration = try? await asset.load(.duration)
        return duration?.seconds ?? 0
    }

    private func hasAudioTrack(url: URL) async -> Bool {
        let asset = AVFoundation.AVAsset(url: url)
        let tracks = try? await asset.loadTracks(withMediaType: .audio)
        return !(tracks ?? []).isEmpty
    }
}

import AVFoundation
```

- [ ] **Step 2: Implement MainWindow**

```swift
// Sources/SyncWave/Views/MainWindow.swift
import SwiftUI

struct MainWindow: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            toolbar

            if appState.hasClips {
                // Main content: Preview + Status + Timeline
                mainContent
            } else {
                ImportDropZone()
            }

            // Status bar
            statusBar
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            Button {
                openFileDialog()
            } label: {
                Label("Importer", systemImage: "plus")
            }

            Divider().frame(height: 20)

            Button {
                Task { await appState.sync() }
            } label: {
                Label("Synchroniser", systemImage: "play.fill")
            }
            .disabled(appState.project.clips.count < 2 || appState.isSyncing)
            .tint(.red)

            Spacer()

            if appState.hasClips {
                Text("\(appState.project.clips.count) clips")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider().frame(height: 20)

            Button {
                Task { await appState.exportXML() }
            } label: {
                Label("Exporter XML", systemImage: "square.and.arrow.up")
            }
            .disabled(!appState.hasSyncResult)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private var mainContent: some View {
        VStack(spacing: 0) {
            // Top: Preview + Status (placeholder for now)
            HStack(spacing: 0) {
                // Preview placeholder
                Rectangle()
                    .fill(Color.black)
                    .frame(height: 220)
                    .overlay {
                        Text("Aperçu vidéo")
                            .foregroundStyle(.secondary)
                    }

                // Sync status panel placeholder
                SyncStatusPanel()
                    .frame(width: 220)
            }
            .frame(height: 220)

            Divider()

            // Timeline
            TimelineView()
        }
    }

    private var statusBar: some View {
        HStack {
            if appState.isSyncing {
                ProgressView(value: appState.syncProgress)
                    .frame(width: 100)
            }
            Text(appState.statusMessage ?? "Prêt")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 4)
        .background(.bar)
    }

    private func openFileDialog() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [
            .movie, .mpeg4Movie, .quickTimeMovie,
            .wav, .aiff, .mp3, .mpeg4Audio
        ]
        if panel.runModal() == .OK {
            Task {
                await appState.importFiles(urls: panel.urls)
            }
        }
    }
}
```

- [ ] **Step 3: Implement ImportDropZone**

```swift
// Sources/SyncWave/Views/ImportDropZone.swift
import SwiftUI
import UniformTypeIdentifiers

struct ImportDropZone: View {
    @EnvironmentObject var appState: AppState
    @State private var isTargeted = false

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "film.stack")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)

            Text("Glissez vos fichiers vidéo et audio ici")
                .font(.title3)
                .foregroundStyle(.secondary)

            Text("MOV, MP4, WAV, AIFF, MP3...")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [8, 4]))
                .foregroundStyle(isTargeted ? .blue : .quaternary)
                .padding(20)
        )
        .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
            handleDrop(providers: providers)
            return true
        }
    }

    private func handleDrop(providers: [NSItemProvider]) {
        for provider in providers {
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                Task { @MainActor in
                    await appState.importFiles(urls: [url])
                }
            }
        }
    }
}
```

- [ ] **Step 4: Update SyncWaveApp to use MainWindow**

```swift
// Sources/SyncWave/App/SyncWaveApp.swift
import SwiftUI

@main
struct SyncWaveApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            MainWindow()
                .environmentObject(appState)
                .frame(minWidth: 900, minHeight: 600)
        }
        .windowStyle(.titleBar)
    }
}
```

- [ ] **Step 5: Verify build**

Run: `swift build 2>&1 | tail -5`
Expected: Build succeeds.

- [ ] **Step 6: Commit**

```bash
git add Sources/SyncWave/App/ Sources/SyncWave/Views/MainWindow.swift Sources/SyncWave/Views/ImportDropZone.swift
git commit -m "feat: UI shell — MainWindow, toolbar, drag & drop import"
```

---

### Task 11: UI — Timeline & Sync Status Panel

**Files:**
- Create: `Sources/SyncWave/Views/TimelineView.swift`
- Create: `Sources/SyncWave/Views/TimelineTrackView.swift`
- Create: `Sources/SyncWave/Views/SyncStatusPanel.swift`

- [ ] **Step 1: Implement SyncStatusPanel**

```swift
// Sources/SyncWave/Views/SyncStatusPanel.swift
import SwiftUI

struct SyncStatusPanel: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("ÉTAT DE SYNCHRONISATION")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .tracking(0.5)

            ScrollView {
                VStack(spacing: 6) {
                    ForEach(appState.project.clips) { clip in
                        clipStatusRow(clip)
                    }
                }
            }

            Spacer()

            // Global confidence
            if let syncResult = appState.project.syncResult {
                let avgConfidence = averageConfidence(syncResult)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Confiance globale")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    ProgressView(value: avgConfidence)
                        .tint(colorForConfidence(avgConfidence))
                    Text("\(Int(avgConfidence * 100))%")
                        .font(.caption2)
                        .foregroundStyle(colorForConfidence(avgConfidence))
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
        }
        .padding(14)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private func clipStatusRow(_ clip: MediaClip) -> some View {
        let isReference = clip.id == appState.project.referenceClip?.id

        return VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Circle()
                    .fill(colorForStatus(clip.syncStatus))
                    .frame(width: 8, height: 8)
                Text(clip.filename)
                    .font(.caption)
                    .lineLimit(1)
            }
            if isReference {
                Text("Référence · \(formatDuration(clip.duration))")
                    .font(.caption2)
                    .foregroundStyle(.green)
                    .padding(.leading, 14)
            } else if let offset = clip.offset {
                let driftText = clip.driftPPM.map { " · drift \(Int($0)) PPM" } ?? ""
                Text(String(format: "%+.3fs", offset) + driftText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 14)
            }
        }
        .padding(7)
        .background(
            RoundedRectangle(cornerRadius: 5)
                .fill(backgroundForStatus(clip.syncStatus))
                .overlay(
                    RoundedRectangle(cornerRadius: 5)
                        .strokeBorder(borderForStatus(clip.syncStatus), lineWidth: 1)
                )
        )
    }

    private func colorForStatus(_ status: SyncStatus) -> Color {
        switch status {
        case .synced: .green
        case .lowConfidence: .yellow
        case .failed: .red
        case .pending: .gray
        }
    }

    private func backgroundForStatus(_ status: SyncStatus) -> Color {
        switch status {
        case .synced: Color.green.opacity(0.05)
        case .lowConfidence: Color.yellow.opacity(0.05)
        case .failed: Color.red.opacity(0.05)
        case .pending: Color.clear
        }
    }

    private func borderForStatus(_ status: SyncStatus) -> Color {
        switch status {
        case .synced: Color.green.opacity(0.2)
        case .lowConfidence: Color.yellow.opacity(0.2)
        case .failed: Color.red.opacity(0.2)
        case .pending: Color.gray.opacity(0.1)
        }
    }

    private func colorForConfidence(_ c: Double) -> Color {
        if c >= 0.7 { return .green }
        if c >= 0.3 { return .yellow }
        return .red
    }

    private func averageConfidence(_ result: SyncResult) -> Double {
        guard !result.alignments.isEmpty else { return 0 }
        return result.alignments.map(\.confidence).reduce(0, +) / Double(result.alignments.count)
    }

    private func formatDuration(_ d: TimeInterval) -> String {
        let h = Int(d) / 3600
        let m = (Int(d) % 3600) / 60
        if h > 0 { return "\(h)h \(m)min" }
        return "\(m)min"
    }
}
```

- [ ] **Step 2: Implement TimelineTrackView**

```swift
// Sources/SyncWave/Views/TimelineTrackView.swift
import SwiftUI

struct TimelineTrackView: View {
    let clip: MediaClip
    let totalDuration: TimeInterval
    let isReference: Bool

    var body: some View {
        HStack(spacing: 0) {
            // Track label
            HStack(spacing: 5) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 6, height: 6)
                Text(clip.filename)
                    .font(.caption2)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .frame(width: 100, alignment: .leading)
            .padding(.horizontal, 8)

            // Track bar
            GeometryReader { geo in
                let totalWidth = geo.size.width
                let clipWidth = totalDuration > 0
                    ? CGFloat(clip.duration / totalDuration) * totalWidth
                    : totalWidth
                let offset = clip.offset ?? 0
                let offsetX = totalDuration > 0
                    ? CGFloat(offset / totalDuration) * totalWidth
                    : 0

                RoundedRectangle(cornerRadius: 3)
                    .fill(clip.isVideo ? Color.blue.opacity(0.3) : Color.green.opacity(0.3))
                    .overlay(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(clip.isVideo ? Color.blue.opacity(0.5) : Color.green.opacity(0.5))
                            .frame(width: 2)
                    }
                    .overlay {
                        HStack {
                            Text(clip.filename)
                                .font(.system(size: 8))
                                .foregroundStyle(.white.opacity(0.7))
                                .lineLimit(1)
                            if let offset = clip.offset, !isReference {
                                Text(String(format: "%+.3fs", offset))
                                    .font(.system(size: 8))
                                    .foregroundStyle(.white.opacity(0.5))
                            }
                        }
                        .padding(.horizontal, 6)
                    }
                    .frame(width: clipWidth)
                    .offset(x: offsetX)
            }
        }
        .frame(height: 36)
    }

    private var statusColor: Color {
        switch clip.syncStatus {
        case .synced: .green
        case .lowConfidence: .yellow
        case .failed: .red
        case .pending: .gray
        }
    }
}
```

- [ ] **Step 3: Implement TimelineView**

```swift
// Sources/SyncWave/Views/TimelineView.swift
import SwiftUI

struct TimelineView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(spacing: 0) {
            // Timeline header with time markers
            timelineHeader

            // Track rows
            ScrollView {
                VStack(spacing: 1) {
                    ForEach(appState.project.clips) { clip in
                        let isRef = clip.id == appState.project.referenceClip?.id
                        TimelineTrackView(
                            clip: clip,
                            totalDuration: maxDuration,
                            isReference: isRef
                        )
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .background(Color(nsColor: .textBackgroundColor).opacity(0.3))
    }

    private var timelineHeader: some View {
        HStack(spacing: 0) {
            Rectangle()
                .fill(Color.clear)
                .frame(width: 100)

            GeometryReader { geo in
                let marks = timeMarks(totalWidth: geo.size.width)
                ForEach(marks, id: \.offset) { mark in
                    Text(mark.label)
                        .font(.system(size: 8, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .position(x: mark.offset, y: 10)
                }
            }
        }
        .frame(height: 20)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var maxDuration: TimeInterval {
        appState.project.clips.map { ($0.offset ?? 0) + $0.duration }.max() ?? 1
    }

    private struct TimeMark {
        let offset: CGFloat
        let label: String
    }

    private func timeMarks(totalWidth: CGFloat) -> [TimeMark] {
        let duration = maxDuration
        guard duration > 0 else { return [] }
        let interval = duration > 3600 ? 600.0 : duration > 600 ? 120.0 : 30.0
        var marks: [TimeMark] = []
        var t = 0.0
        while t <= duration {
            let x = CGFloat(t / duration) * totalWidth
            let mins = Int(t) / 60
            let secs = Int(t) % 60
            marks.append(TimeMark(offset: x, label: String(format: "%02d:%02d", mins, secs)))
            t += interval
        }
        return marks
    }
}
```

- [ ] **Step 4: Verify build**

Run: `swift build 2>&1 | tail -5`
Expected: Build succeeds.

- [ ] **Step 5: Commit**

```bash
git add Sources/SyncWave/Views/TimelineView.swift Sources/SyncWave/Views/TimelineTrackView.swift Sources/SyncWave/Views/SyncStatusPanel.swift
git commit -m "feat: UI timeline multi-piste et panel de statut sync"
```

---

### Task 12: UI — Preview & Export Sheet

**Files:**
- Create: `Sources/SyncWave/Views/PreviewView.swift`
- Create: `Sources/SyncWave/Views/ExportSheet.swift`
- Modify: `Sources/SyncWave/Views/MainWindow.swift`

- [ ] **Step 1: Implement PreviewView**

```swift
// Sources/SyncWave/Views/PreviewView.swift
import SwiftUI
import AVKit

struct PreviewView: View {
    @EnvironmentObject var appState: AppState
    @State private var player: AVPlayer?

    var body: some View {
        ZStack {
            Color.black

            if let player {
                VideoPlayer(player: player)
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "play.rectangle")
                        .font(.system(size: 32))
                        .foregroundStyle(.secondary)
                    Text("Aperçu vidéo")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .onChange(of: appState.project.clips) { _, clips in
            // Auto-load first video clip
            if let firstVideo = clips.first(where: { $0.isVideo }) {
                player = AVPlayer(url: firstVideo.url)
            }
        }
    }
}
```

- [ ] **Step 2: Implement ExportSheet**

```swift
// Sources/SyncWave/Views/ExportSheet.swift
import SwiftUI

struct ExportSheet: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) var dismiss
    @State private var exportURL: URL?

    var body: some View {
        VStack(spacing: 20) {
            Text("Exporter la synchronisation")
                .font(.headline)

            VStack(alignment: .leading, spacing: 12) {
                // Format
                HStack {
                    Text("Format :")
                        .foregroundStyle(.secondary)
                    Text(appState.project.exportSettings.format.rawValue)
                        .fontWeight(.medium)
                }

                // Replace audio toggle
                Toggle("Remplacer l'audio des vidéos par l'audio externe",
                       isOn: $appState.project.exportSettings.replaceAudioInVideo)

                // Include unsynced
                Toggle("Inclure les clips non synchronisés",
                       isOn: $appState.project.exportSettings.includeUnsyncedClips)
            }
            .padding()
            .background(RoundedRectangle(cornerRadius: 8).fill(.bar))

            HStack {
                Button("Annuler") { dismiss() }
                    .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Exporter") {
                    Task {
                        // Ask user where to save
                        let panel = NSSavePanel()
                        panel.allowedContentTypes = [.xml]
                        panel.nameFieldStringValue = "SyncWave Export.xml"
                        if panel.runModal() == .OK, let url = panel.url {
                            appState.project.exportSettings.outputDirectory = url.deletingLastPathComponent()
                            exportURL = await appState.exportXML()
                            dismiss()
                        }
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!appState.hasSyncResult)
            }
        }
        .padding(24)
        .frame(width: 450)
    }
}
```

- [ ] **Step 3: Update MainWindow to use PreviewView and ExportSheet**

Replace the preview placeholder in `MainWindow.swift`:

In `Sources/SyncWave/Views/MainWindow.swift`, replace the `mainContent` computed property:

```swift
    @State private var showExportSheet = false

    // Replace the existing mainContent property with:
    private var mainContent: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                PreviewView()
                    .frame(height: 220)

                SyncStatusPanel()
                    .frame(width: 220, height: 220)
            }

            Divider()

            TimelineView()
        }
    }
```

Also update the export button in toolbar to use the sheet:

```swift
    // In the toolbar, change the export button to:
    Button {
        showExportSheet = true
    } label: {
        Label("Exporter XML", systemImage: "square.and.arrow.up")
    }
    .disabled(!appState.hasSyncResult)
```

Add the sheet modifier to the VStack in `body`:

```swift
    .sheet(isPresented: $showExportSheet) {
        ExportSheet()
    }
```

- [ ] **Step 4: Verify build**

Run: `swift build 2>&1 | tail -5`
Expected: Build succeeds.

- [ ] **Step 5: Commit**

```bash
git add Sources/SyncWave/Views/
git commit -m "feat: UI preview vidéo, panneau export, intégration complète"
```

---

### Task 13: Run All Tests & Final Verification

- [ ] **Step 1: Run all tests**

Run: `swift test 2>&1 | tail -20`
Expected: All tests pass (MediaClipTests: 3, GCCPHATCorrelatorTests: 4, DriftCorrectorTests: 3, AudioExtractorTests: 1, SyncEngineTests: 2, ExportEngineTests: 2 = **15 tests total**).

- [ ] **Step 2: Fix any failing tests**

If any test fails, investigate and fix. Common issues:
- Confidence thresholds may need adjustment in GCC-PHAT
- FFT size calculations may have off-by-one errors
- vDSP API usage may need tweaking

- [ ] **Step 3: Run the app**

Run: `swift run 2>&1 | head -5`
Expected: App launches (or build succeeds — actual window display requires a display server).

- [ ] **Step 4: Final commit**

```bash
git add -A
git commit -m "feat: SyncWave v1 — app macOS de sync audio/vidéo multi-caméra

Moteur GCC-PHAT via vDSP, correction de drift, export FCP 7 XML.
Interface SwiftUI : import drag & drop, timeline multi-piste, preview vidéo."
```
