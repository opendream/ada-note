import XCTest
@testable import MeetingCore

final class RecorderPathsTests: XCTestCase {
    func testEnvironmentOverrideWinsEvenWhenTheFileIsMissing() {
        let path = RecorderPaths.script(
            environment: ["ADA_NOTE_RECORDER": "  /opt/meeting.py  "],
            home: "/home/someone",
            executable: URL(fileURLWithPath: "/src/ada-note/.build/debug/MeetingWindow"),
            fileExists: { _ in false }
        )
        XCTAssertEqual(path, "/opt/meeting.py")
    }

    func testBlankOverrideFallsThrough() {
        let home = "/home/someone"
        let path = RecorderPaths.script(
            environment: ["ADA_NOTE_RECORDER": "   "],
            home: home,
            executable: URL(fileURLWithPath: "/tmp/MeetingWindow"),
            fileExists: { _ in false }
        )
        XCTAssertEqual(path, RecorderPaths.marketplaceScript(home: home))
    }

    func testInstalledSkillWinsOverASiblingCheckout() {
        let home = "/home/someone"
        let market = RecorderPaths.marketplaceScript(home: home)
        let sibling = "/src/noomz-claude-skills/skills/meeting-secretary/scripts/meeting.py"
        let path = RecorderPaths.script(
            environment: [:],
            home: home,
            executable: URL(fileURLWithPath: "/src/ada-note/.build/debug/MeetingWindow"),
            fileExists: { $0 == market || $0 == sibling }
        )
        XCTAssertEqual(path, market)
    }

    func testSiblingCheckoutIsUsedWhenTheMarketplaceCopyIsMissing() {
        let sibling = "/src/noomz-claude-skills/skills/meeting-secretary/scripts/meeting.py"
        let path = RecorderPaths.script(
            environment: [:],
            home: "/home/someone",
            executable: URL(fileURLWithPath: "/src/ada-note/.build/debug/MeetingWindow"),
            fileExists: { $0 == sibling }
        )
        XCTAssertEqual(path, sibling)
    }

    func testSkillVocabSitsBesideTheScript() {
        let script = "/opt/skills/meeting-secretary/scripts/meeting.py"
        let vocab = "/opt/skills/meeting-secretary/assets/vocab.txt"
        XCTAssertEqual(
            RecorderPaths.skillVocab(script: script, fileExists: { $0 == vocab })?.path,
            vocab
        )
        XCTAssertNil(RecorderPaths.skillVocab(script: script, fileExists: { _ in false }))
    }
}
