import XCTest
@testable import MeetingCore

final class MeetingRootTests: XCTestCase {
    func testTempDirWithoutGitResolvesToItself() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir.appendingPathComponent(".git").path))
        let root = MeetingRoot.meetingsDirectory(picked: dir.path, environment: [:])
        XCTAssertEqual(root.path, dir.appendingPathComponent(".meetings").path)
        XCTAssertEqual(root.deletingLastPathComponent().path, dir.path)
    }

    func testMeetingHomeWinsAndDoesNotAskGit() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var calls = 0
        let root = MeetingRoot.meetingsDirectory(picked: dir.path, environment: ["MEETING_HOME": home.path]) { _ in
            calls += 1
            return "/somewhere"
        }
        XCTAssertEqual(calls, 0)
        XCTAssertEqual(root.path, home.path)
    }

    func testGitTopLevelBeatsThePickedSubfolder() {
        let root = MeetingRoot.meetingsDirectory(picked: "/repo/sub", environment: [:]) { picked in
            XCTAssertEqual(picked, "/repo/sub")
            return "/repo"
        }
        XCTAssertEqual(root.path, "/repo/.meetings")
    }

    func testFailedGitLookupUsesThePickedFolder() {
        let root = MeetingRoot.meetingsDirectory(picked: "/repo/sub", environment: [:]) { _ in nil }
        XCTAssertEqual(root.path, "/repo/sub/.meetings")
    }
}
