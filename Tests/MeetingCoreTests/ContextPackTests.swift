import XCTest
@testable import MeetingCore

final class ContextPackTests: XCTestCase {
    func testCutsAt3000AndSkipsNothingPassedIn() {
        let big = String(repeating: "a", count: 2900)
        let result = ContextPack.build(files: [
            PackedFile(path: "CLAUDE.md", text: big),
            PackedFile(path: "README.md", text: String(repeating: "b", count: 500))
        ])
        XCTAssertEqual(result.files, ["CLAUDE.md"])
        XCTAssertTrue(result.cut)
        XCTAssertTrue(result.text.contains("Pack was cut at 3000 characters."))
        XCTAssertLessThanOrEqual(result.text.count, 3000 + "\n\nPack was cut at 3000 characters.".count)
    }

    func testDiscoverySkipsMissingAndScansPlansOnlyWithATopic() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("plans"), withIntermediateDirectories: true)
        try "rules".write(to: root.appendingPathComponent("CLAUDE.md"), atomically: true, encoding: .utf8)
        try "ship".write(to: root.appendingPathComponent("plans/standup.md"), atomically: true, encoding: .utf8)
        let noTopic = ContextFiles.paths(root: root, topicTerms: [], meetingVocab: nil, skillVocab: nil)
        XCTAssertEqual(noTopic.map(\.lastPathComponent), ["CLAUDE.md"])
        let withTopic = ContextFiles.paths(root: root, topicTerms: ["standup"], meetingVocab: nil, skillVocab: nil)
        XCTAssertEqual(withTopic.map(\.lastPathComponent), ["CLAUDE.md", "standup.md"])
    }
}
