import XCTest
@testable import MeetingCore

final class LiveNotesTests: XCTestCase {
    func testKeepsEmojiLinesAndDropsGist() {
        let reply = "📌 Sam → ship the fix (Friday)\n· 10:01 quiet talk"
        XCTAssertEqual(
            LiveNotes.entries(from: reply, stamp: "10:01:02"),
            ["- [10:01:02] 📌 Sam → ship the fix (Friday)"]
        )
    }
}
