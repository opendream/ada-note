import XCTest
@testable import MeetingCore

final class LogStatusTests: XCTestCase {
    func testMapsRecorderLines() {
        XCTAssertEqual(LogStatus.classify("ERROR recorder exited by itself — check microphone permission"), .microphonePermission)
        XCTAssertEqual(LogStatus.classify("12:00:00 ERROR no audio for 40 s — capture stalled"), .captureStalled)
        XCTAssertEqual(LogStatus.classify("12:00:40 audio resumed"), .audioResumed)
        XCTAssertEqual(LogStatus.classify("meeting-capture: process tap failed, OSStatus 1"), .systemAudioPermission)
        XCTAssertEqual(LogStatus.classify("grant System Audio Recording permission"), .systemAudioPermission)
        XCTAssertEqual(LogStatus.classify("WARNING: no running app named (or with bundle id) --tap-app 'zoom.us'"), .tapAppMissing)
        XCTAssertEqual(LogStatus.classify("10:00:00 ERROR vad: boom"), .sliceMissed)
        XCTAssertEqual(LogStatus.classify("10:00:00 ERROR window: boom"), .sliceMissed)
        XCTAssertEqual(LogStatus.classify("ERROR chunk 00001.wav: bad"), .sliceMissed)
        XCTAssertNil(LogStatus.classify("meeting-capture: levels: mic=-20"))
    }

    func testMicrophoneCopy() {
        XCTAssertEqual(
            LogStatus.message(for: .microphonePermission),
            "Microphone permission. Recording has stopped, and audio from here on is not kept."
        )
    }
}
