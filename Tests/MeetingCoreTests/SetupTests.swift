import XCTest
@testable import MeetingCore

final class SetupTests: XCTestCase {
    func testCommandsNameTheRealInstallSteps() {
        let commands = Setup.commands(root: URL(fileURLWithPath: "/tmp/transcribe.cpp"), missingFfmpeg: true, missingSwiftc: true)
        let text = commands.joined(separator: "\n")
        XCTAssertTrue(text.contains("git clone https://github.com/handy-computer/transcribe.cpp"))
        XCTAssertTrue(text.contains("Qwen3-ASR-1.7B-Q8_0.gguf"))
        XCTAssertTrue(text.contains("silero-vad-v6.2-F32.gguf"))
        XCTAssertTrue(text.contains("brew install ffmpeg"))
        XCTAssertTrue(text.contains("xcode-select --install"))
        XCTAssertFalse(text.contains("meeting.py start"))
    }
}
