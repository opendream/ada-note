import XCTest
@testable import MeetingCore

final class NotePromptTests: XCTestCase {
    func testDropsSilenceAndMarksAShortenedTranscript() {
        let speech = "[10:00:00] " + String(repeating: "x", count: 4000)
        let silence = "[10:00:20] (silence)"
        let more = "[10:00:40] " + String(repeating: "y", count: 4000)
        let note = NotePrompt.ollama(
            pack: "PACK",
            packFiles: ["CLAUDE.md"],
            template: "TEMPLATE",
            transcript: [speech, silence, more].joined(separator: "\n")
        )
        XCTAssertTrue(note.shortened)
        XCTAssertTrue(note.prompt.contains("Pack files: CLAUDE.md"))
        XCTAssertTrue(note.prompt.contains("Transcript was shortened."))
        XCTAssertFalse(note.prompt.contains("(silence)"))
        XCTAssertLessThanOrEqual(note.prompt.count, 7000 + "Transcript was shortened.\n".count)
    }

    func testChatKeepsSystemAndFitsIn7000() {
        var chat = OllamaChat(system: String(repeating: "s", count: 100))
        chat.add(user: String(repeating: "u", count: 3000), assistant: String(repeating: "a", count: 3000))
        chat.add(user: "latest", assistant: "reply")
        let fitted = chat.fitting()
        XCTAssertEqual(fitted.first?.role, "system")
        XCTAssertEqual(fitted.last?.content, "reply")
        XCTAssertEqual(fitted.count, chat.messages.count)
        let total = fitted.reduce(0) { $0 + $1.content.count }
        XCTAssertEqual(total, 6111)
        XCTAssertLessThanOrEqual(total, 7000)
    }

    func testFittingDropsOlderTurnsAndKeepsTheNewestUser() {
        var chat = OllamaChat(system: "s")
        chat.add(user: String(repeating: "u", count: 4000), assistant: String(repeating: "a", count: 4000))
        chat.messages.append(OllamaMessage(role: "user", content: String(repeating: "n", count: 2000)))
        let fitted = chat.fitting()
        XCTAssertEqual(fitted.map(\.role), ["system", "user"])
        XCTAssertEqual(fitted.last?.content.count, 2000)
        XCTAssertLessThanOrEqual(fitted.reduce(0) { $0 + $1.content.count }, 7000)
    }

    func testFittingSkipsAUserMessageThatCannotFitWithTheSystemMessage() {
        var chat = OllamaChat(system: String(repeating: "s", count: 100))
        chat.messages.append(OllamaMessage(role: "user", content: String(repeating: "u", count: 6901)))
        XCTAssertTrue(chat.fitting().isEmpty)
    }

    func testOllamaNoteKeepsBothTranscriptsAndLiveNotes() {
        let note = NotePrompt.ollama(
            pack: "PACK",
            packFiles: ["CLAUDE.md"],
            template: "TEMPLATE",
            transcript: "[10:00:00] final 42\n[10:00:20] (silence)",
            liveTranscript: "[10:00:00] live forty-two\n[10:00:20] (silence)",
            liveNotes: "- [10:00:00] 📌 ship"
        )
        XCTAssertTrue(note.prompt.contains("final 42"))
        XCTAssertTrue(note.prompt.contains("live forty-two"))
        XCTAssertTrue(note.prompt.contains("📌 ship"))
        XCTAssertFalse(note.prompt.contains("(silence)"))
        XCTAssertFalse(note.shortened)
        XCTAssertLessThanOrEqual(note.prompt.count, 7000)
    }
}
