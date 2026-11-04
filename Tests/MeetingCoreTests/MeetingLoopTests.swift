import XCTest
@testable import MeetingCore

final class MeetingLoopTests: XCTestCase {
    func testCannedPinIsLoggedAndGistIsNot() {
        let session = FakeSession(reply: "📌 Sam → ship (Friday)\n· 10:00 quiet")
        let loop = MeetingLoop(session: session)
        loop.onSpeech(TranscriptLine.parse("[10:00:00] ship it")!)
        XCTAssertEqual(loop.notes, "- [10:00:00] 📌 Sam → ship (Friday)\n")
        XCTAssertEqual(session.prompts, ["[10:00:00] ship it"])
        XCTAssertFalse(loop.tailStopped)
    }

    func testFailureSetsReconnectAndLeavesTheTailRunning() {
        let session = FakeSession(reply: "")
        session.fail = true
        let loop = MeetingLoop(session: session)
        loop.onSpeech(TranscriptLine.parse("[10:00:00] hello")!)
        XCTAssertEqual(loop.status, "backend dead")
        XCTAssertFalse(loop.tailStopped)
        XCTAssertEqual(loop.notes, "")
    }

    func testSilenceDoesNotSend() {
        let session = FakeSession(reply: "📌 x")
        let loop = MeetingLoop(session: session)
        loop.onSpeech(TranscriptLine.parse("[10:00:00] (silence)")!)
        XCTAssertTrue(session.prompts.isEmpty)
    }

    func testWaitingAt30SecondsDoesNotFinishTheTurn() {
        let start = Date(timeIntervalSince1970: 0)
        XCTAssertEqual(TurnWatch.watch(started: start, now: start.addingTimeInterval(29), finished: false), .running)
        XCTAssertEqual(TurnWatch.watch(started: start, now: start.addingTimeInterval(30), finished: false), .waiting)
        XCTAssertEqual(TurnWatch.watch(started: start, now: start.addingTimeInterval(31), finished: true), .done)
    }
}
