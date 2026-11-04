import XCTest
@testable import MeetingCore

final class StartGateTests: XCTestCase {
    func testStartRequiresConsentAndPreflight() {
        var gate = StartGate(project: "/repo", name: "2026-11-03-standup", consent: false, backendReady: true, recognizerReady: true, alreadyRecording: false, nameTaken: false)
        XCTAssertFalse(gate.canStart)
        gate.consent = true
        XCTAssertTrue(gate.canStart)
        gate.alreadyRecording = true
        XCTAssertFalse(gate.canStart)
        gate.alreadyRecording = false
        gate.name = "bad name"
        XCTAssertFalse(gate.canStart)
        gate.name = "2026-11-03-standup"
        gate.nameTaken = true
        XCTAssertFalse(gate.canStart)
        gate.nameTaken = false
        gate.backendReady = false
        XCTAssertFalse(gate.canStart)
        gate.backendReady = true
        gate.recognizerReady = false
        XCTAssertFalse(gate.canStart)
        gate.recognizerReady = true
        gate.project = ""
        XCTAssertFalse(gate.canStart)
        gate.project = "/repo"
        XCTAssertTrue(gate.canStart)
    }

    func testOllamaNeedsTheModelAndClaudeNeedsAPing() {
        XCTAssertFalse(BackendCheck(onPath: true, ollamaUp: false, hasModel: false, pingOK: true).ready(for: .ollama))
        XCTAssertTrue(BackendCheck(onPath: true, ollamaUp: true, hasModel: true, pingOK: false).ready(for: .ollama))
        XCTAssertFalse(BackendCheck(onPath: true, ollamaUp: false, hasModel: false, pingOK: false).ready(for: .claude))
        XCTAssertTrue(BackendCheck(onPath: true, ollamaUp: false, hasModel: false, pingOK: true).ready(for: .claude))
        XCTAssertFalse(BackendCheck(onPath: false, ollamaUp: true, hasModel: true, pingOK: true).ready(for: .ollama))
        XCTAssertFalse(BackendCheck(onPath: false, ollamaUp: true, hasModel: true, pingOK: true).ready(for: .claude))
    }

    func testAttachUsesNotesAndTheLast20Lines() {
        var lines = (1...25).map { TranscriptLine(stamp: "10:00:\($0)", text: "n\($0)", kind: .speech) }
        lines.insert(TranscriptLine(stamp: "09:59", text: "(silence)", kind: .silence), at: 0)
        lines.insert(TranscriptLine(stamp: "10:00:00", text: "(silence — prompt echo)", kind: .promptEcho), at: 10)
        lines.append(TranscriptLine(stamp: "", text: "[END]", kind: .end))
        let notes = "- [10:00:01] 📌 a"
        let prompt = AttachBrief.prompt(notes: notes, recent: lines)
        XCTAssertTrue(prompt.contains("📌 a"))
        XCTAssertTrue(prompt.contains("n6"))
        XCTAssertTrue(prompt.contains("n25"))
        let rows = prompt.components(separatedBy: "\n")
        XCTAssertEqual(rows.first, notes)
        let speech = rows.enumerated().compactMap { index, row -> String? in
            guard index > 0 else { return nil }
            return speechText(row)
        }
        XCTAssertEqual(speech.first, "n6")
        XCTAssertEqual(speech.last, "n25")
        XCTAssertEqual(speech, (6...25).map { "n\($0)" })
        XCTAssertFalse(prompt.contains("(silence)"))
        XCTAssertFalse(prompt.contains("[END]"))
    }

    func testPrivacyLines() {
        XCTAssertEqual(PrivacyNotice.text(for: .ollama), "Transcript text stays on this Mac.")
        XCTAssertEqual(PrivacyNotice.text(for: .claude), "Transcript text leaves the Mac.")
        XCTAssertEqual(PrivacyNotice.text(for: .codex), "Transcript text leaves the Mac.")
        XCTAssertEqual(PrivacyNotice.text(for: .agy), "Transcript text leaves the Mac.")
    }

    func testRecognizerReadyOnlyWhenAllFiveAreTrue() {
        let ready = RecognizerCheck(cli: true, model: true, vad: true, ffmpeg: true, swiftc: true).ready
        let missingOne = [
            RecognizerCheck(cli: false, model: true, vad: true, ffmpeg: true, swiftc: true),
            RecognizerCheck(cli: true, model: false, vad: true, ffmpeg: true, swiftc: true),
            RecognizerCheck(cli: true, model: true, vad: false, ffmpeg: true, swiftc: true),
            RecognizerCheck(cli: true, model: true, vad: true, ffmpeg: false, swiftc: true),
            RecognizerCheck(cli: true, model: true, vad: true, ffmpeg: true, swiftc: false)
        ].map(\.ready)
        XCTAssertEqual(ready && missingOne == [false, false, false, false, false], true)
    }

    func testNewestUnnotedReturnsTheNewerFolder() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? fm.removeItem(at: root) }
        let older = root.appendingPathComponent("older")
        let newer = root.appendingPathComponent("newer")
        try fm.createDirectory(at: older, withIntermediateDirectories: true)
        try fm.createDirectory(at: newer, withIntermediateDirectories: true)
        let olderMeta = older.appendingPathComponent("meta.json")
        let newerMeta = newer.appendingPathComponent("meta.json")
        try Data("{}".utf8).write(to: olderMeta)
        try Data("{}".utf8).write(to: newerMeta)
        try Data("note".utf8).write(to: older.appendingPathComponent("summary.md"))
        let oldDate = Date(timeIntervalSince1970: 1_700_000_000)
        let newDate = Date(timeIntervalSince1970: 1_800_000_000)
        try fm.setAttributes([.modificationDate: oldDate], ofItemAtPath: olderMeta.path)
        try fm.setAttributes([.modificationDate: newDate], ofItemAtPath: newerMeta.path)
        try fm.setAttributes([.modificationDate: newDate], ofItemAtPath: older.path)
        try fm.setAttributes([.modificationDate: oldDate], ofItemAtPath: newer.path)

        XCTAssertEqual(PastMeetings.newestUnnoted(root: root)?.lastPathComponent, "newer")

        try fm.setAttributes([.modificationDate: Date(timeIntervalSince1970: 1_900_000_000)], ofItemAtPath: olderMeta.path)
        XCTAssertEqual(PastMeetings.newestUnnoted(root: root)?.lastPathComponent, "newer")
    }

    private func speechText(_ row: String) -> String? {
        guard row.hasPrefix("["), let close = row.range(of: "] ") else { return nil }
        return String(row[close.upperBound...])
    }
}
