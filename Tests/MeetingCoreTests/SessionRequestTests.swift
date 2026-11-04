import XCTest
@testable import MeetingCore

final class SessionRequestTests: XCTestCase {
    func testClaudeLiveIsReadOnly() {
        let args = ClaudeLaunch.liveArgv(project: "/repo")
        XCTAssertTrue(args.contains("--restricted"))
        XCTAssertTrue(args.contains("Read,Grep,Glob"))
        XCTAssertTrue(args.contains("Bash,Edit,Write"))
        XCTAssertFalse(args.contains("--dangerously-skip-permissions"))
        let live = Prompts.live(project: "/repo")
        XCTAssertTrue(live.contains("/repo"))
        XCTAssertTrue(live.contains("🔎 queued"))
        let rules = "Reply rules, first match, combined when a batch holds several."
        guard let rulesAt = live.range(of: rules), let tableAt = live.range(of: "| Heard | Reply |") else {
            return XCTFail("missing reply rules above the table")
        }
        let between = live[rulesAt.upperBound..<tableAt.lowerBound]
        XCTAssertTrue(between.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    func testClaudeNoteAddsGhOnly() {
        let args = ClaudeLaunch.noteArgv(project: "/repo", sessionID: "sid")
        XCTAssertTrue(args.contains("--resume"))
        XCTAssertTrue(args.contains("sid"))
        XCTAssertTrue(args.contains("Read,Grep,Glob,Bash(gh *)"))
        XCTAssertTrue(args.contains("Edit,Write"))
        XCTAssertFalse(args.contains("--restricted"))
        XCTAssertFalse(args.joined(separator: " ").contains("bypass"))
        XCTAssertTrue(Prompts.noteTemplate.contains("Write the note in English."))
        XCTAssertTrue(Prompts.noteTemplate.contains("Leave quotes as spoken."))
        XCTAssertTrue(Prompts.noteTemplate.contains("Where the two transcripts disagree on a number, name, date, id, or issue number, the figure is (?) and both wordings are quoted."))
        XCTAssertTrue(Prompts.noteTemplate.contains("`gh pr view`"))
        XCTAssertTrue(Prompts.noteTemplate.contains("`gh issue view`"))
        XCTAssertTrue(Prompts.noteTemplate.contains("`gh issue list`"))
        XCTAssertTrue(Prompts.noteTemplate.contains("must not comment, push, or post"))
    }

    func testAgyAndCodexStayInPlanAndReadOnly() {
        XCTAssertEqual(AgyLaunch.liveArgv(), ["agy", "--print", "--input-format", "stream-json", "--output-format", "stream-json", "--mode", "plan"])
        XCTAssertTrue(AgyLaunch.noteArgv(sessionID: "c1").contains("--conversation"))
        XCTAssertFalse(CodexLaunch.execArgv(project: "/repo", gitRepo: true).contains("--skip-git-repo-check"))
        XCTAssertTrue(CodexLaunch.execArgv(project: "/not-git", gitRepo: false).contains("--skip-git-repo-check"))
        let resume = CodexLaunch.resumeArgv(id: "tid", project: "/repo", gitRepo: true)
        XCTAssertEqual(resume.prefix(4).map { $0 }, ["codex", "exec", "resume", "tid"])
        XCTAssertTrue(resume.contains("read-only"))
        XCTAssertFalse(resume.joined(separator: " ").contains("dangerously-bypass"))
    }

    func testOllamaBodyAndSessionIDs() throws {
        let chat = OllamaChat(system: "pack")
        let body = try JSONSerialization.jsonObject(with: OllamaLaunch.body(chat: chat)) as! [String: Any]
        XCTAssertEqual(body["model"] as? String, "qwen3.8")
        let options = body["options"] as! [String: Any]
        XCTAssertEqual(options["num_ctx"] as? Int, 8192)
        XCTAssertEqual(SessionID.parse(from: "{\"type\":\"system\",\"session_id\":\"abc\"}"), "abc")
        XCTAssertEqual(SessionID.parse(from: "session id: 11111111-1111-1111-1111-111111111111"), "11111111-1111-1111-1111-111111111111")
    }
}
