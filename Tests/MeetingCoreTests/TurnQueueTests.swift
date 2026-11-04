import XCTest
@testable import MeetingCore

final class TurnQueueTests: XCTestCase {
    func testQuestionJumpsAheadOfQueuedSpeech() {
        var queue = TurnQueue()
        let first = TranscriptLine.parse("[10:00:00] one")!
        let second = TranscriptLine.parse("[10:00:20] two")!
        queue.pushSpeech(first)
        XCTAssertEqual(queue.takeNext(), .speech(SpeechBatch(lines: [first])))
        queue.pushSpeech(second)
        XCTAssertNil(queue.takeNext())
        queue.pushQuestion("what did we ship")
        queue.finish()
        XCTAssertEqual(queue.takeNext(), .question("what did we ship"))
        queue.finish()
        XCTAssertEqual(queue.takeNext(), .speech(SpeechBatch(lines: [second])))
    }

    func testSilenceIsIgnored() {
        var queue = TurnQueue()
        queue.pushSpeech(TranscriptLine.parse("[10:00:00] (silence)")!)
        XCTAssertNil(queue.takeNext())
    }
}
