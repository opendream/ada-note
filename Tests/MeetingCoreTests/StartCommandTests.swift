import XCTest
@testable import MeetingCore

final class StartCommandTests: XCTestCase {
    func testMicAndLangOnly() {
        let cmd = StartCommand(
            python: "python3",
            script: "/skill/scripts/meeting.py",
            workingDirectory: "/repo",
            name: "2026-11-03-standup",
            device: "default",
            lang: "th",
            tapApp: nil,
            replayWav: nil
        )
        XCTAssertEqual(cmd.workingDirectory, "/repo")
        XCTAssertEqual(cmd.argv(), [
            "python3", "/skill/scripts/meeting.py", "start", "2026-11-03-standup",
            "--device", "default", "--lang", "th"
        ])
        XCTAssertFalse(cmd.argv().contains("--screen"))
        XCTAssertFalse(cmd.argv().contains("--app"))
        XCTAssertEqual(cmd.argv().filter { $0 == "--device" }.count, 1)
    }

    func testTapAndReplay() {
        let cmd = StartCommand(
            python: "python3",
            script: "/skill/scripts/meeting.py",
            workingDirectory: "/repo",
            name: "replay",
            device: "default",
            lang: "en",
            tapApp: "zoom.us",
            replayWav: "/tmp/call.wav"
        )
        let args = cmd.argv()
        XCTAssertEqual(Array(args.suffix(4)), ["--tap-app", "zoom.us", "--replay", "/tmp/call.wav"])
        XCTAssertEqual(args.filter { $0 == "--device" }.count, 1)
    }
}
