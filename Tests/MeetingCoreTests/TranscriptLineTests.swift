import XCTest
@testable import MeetingCore

final class TranscriptLineTests: XCTestCase {
    func testSpeech() {
        let line = TranscriptLine.parse("[10:01:02] hello")
        XCTAssertEqual(line?.kind, .speech)
        XCTAssertEqual(line?.stamp, "10:01:02")
        XCTAssertEqual(line?.text, "hello")
        XCTAssertEqual(line?.callsModel, true)
    }

    func testSilenceDoesNotCallTheModel() {
        XCTAssertEqual(TranscriptLine.parse("[10:01:02] (silence)")?.kind, .silence)
        XCTAssertEqual(TranscriptLine.parse("[10:01:02] (silence — prompt echo)")?.kind, .promptEcho)
        XCTAssertEqual(TranscriptLine.parse("[10:01:02] (silence)")?.callsModel, false)
        XCTAssertEqual(TranscriptLine.parse("[10:01:02] (silence — prompt echo)")?.callsModel, false)
    }

    func testEnd() {
        XCTAssertEqual(TranscriptLine.parse("[END]")?.kind, .end)
    }
}
