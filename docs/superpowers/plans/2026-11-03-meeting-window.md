# Meeting window implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A small always-on-top Mac window that records with the existing meeting-secretary recorder, shows live secretary lines from Claude Code, Codex, Antigravity, or Ollama, and writes a fact-checked `summary.md` on Stop.

**Architecture:** A Swift package. `MeetingCore` holds every rule that can be tested without a microphone or a live CLI. The `MeetingWindow` executable is a SwiftUI panel that calls those types and spawns `meeting.py`. Sessions are built as argv and HTTP bodies so tests never start Claude, Codex, Antigravity, or Ollama.

**Tech Stack:** Swift 5.9, SwiftUI, macOS 14, XCTest, the existing Python recorder.

**Spec:** `docs/superpowers/specs/2026-11-03-meeting-window-design.md`

## Global Constraints

- App root is this repository. Do not modify the meeting-secretary checkout.
- Recorder command is `python3` plus the resolved `meeting.py`, with cwd set to the project folder the user picked.
- One mic device. Never pass `--screen`, `--app`, or a second `--device`.
- Recognizer language defaults to `th`. The note is English. Quotes stay as spoken.
- Start stays off until a project folder is set, the meeting name matches `[A-Za-z0-9._-]+`, consent is checked, the recognizer preflight passed, and the backend preflight passed.
- Silence and `(silence — prompt echo)` do not call the model. One model turn at a time. A typed question is the next prompt ahead of queued speech.
- The window writes `live-notes.md` and `summary.md`. The model returns text only. Summary names advance `summary.md`, `summary-v2.md`, `summary-v3.md`.
- Context pack cap is 3000 characters. Ollama note budget and Ollama chat trim are 7000 characters. Ollama model is `qwen3.8`, `num_ctx` 8192, URL `http://127.0.0.1:11434`.
- Live cloud tools are Read, Grep, Glob only. No Bash, Edit, Write, and no bypass-permissions flag. The note may add `Bash(gh *)` for `gh pr view`, `gh issue view`, and `gh issue list`.
- A turn with no reply for 30 seconds stays queued. A second turn does not start. The transcript tail keeps running.
- Audio stays under `<project>/.meetings/`. v1 does not record the screen, post the note, or edit the project.
- Automated tests do not call a live CLI, the microphone, or the network.

## File structure

- `Package.swift` defines `MeetingCore`, `MeetingCoreTests`, and the `MeetingWindow` executable.
- `Sources/MeetingCore/MeetingName.swift` validates names and builds the default name.
- `Sources/MeetingCore/StartCommand.swift` builds the `meeting.py start` argv.
- `Sources/MeetingCore/TranscriptLine.swift` parses one transcript line.
- `Sources/MeetingCore/TurnQueue.swift` holds one in-flight turn, questions first.
- `Sources/MeetingCore/LiveNotes.swift` keeps emoji replies and drops gist lines.
- `Sources/MeetingCore/SummaryNames.swift` picks the next summary filename.
- `Sources/MeetingCore/LogStatus.swift` maps recorder log lines to a status.
- `Sources/MeetingCore/ContextPack.swift` builds the Ollama pack.
- `Sources/MeetingCore/NotePrompt.swift` builds the Ollama note prompt and trims Ollama chat.
- `Sources/MeetingCore/Prompts.swift` holds the live rules and the note template.
- `Sources/MeetingCore/Sessions.swift` builds Claude, Antigravity, Codex, and Ollama requests.
- `Sources/MeetingCore/MeetingLoop.swift` pumps the queue through a session into live notes.
- `Sources/MeetingCore/RecorderClient.swift` parses status, start, and stop output.
- `Sources/MeetingCore/StartGate.swift` decides whether Start is enabled and builds the attach brief.
- `Sources/MeetingCore/MeetingModel.swift` is the state the window binds to.
- `Sources/MeetingWindow/MeetingWindowApp.swift` is the SwiftUI panel.
- `Info.plist` and `scripts/bundle-app.sh` wrap the binary as `Ada Note.app`.
- Tests live in `Tests/MeetingCoreTests/` and mirror those types.

---

### Task 1: Package and meeting name

**Files:**
- Create: `Package.swift`
- Create: `Sources/MeetingCore/MeetingName.swift`
- Test: `Tests/MeetingCoreTests/MeetingNameTests.swift`

**Interfaces:**
- Consumes: nothing
- Produces: `MeetingName.isValid(_:) -> Bool`, `MeetingName.defaultName(date:slug:) -> String`

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import MeetingCore

final class MeetingNameTests: XCTestCase {
    func testRejectsEmptyAndSlashes() {
        XCTAssertFalse(MeetingName.isValid(""))
        XCTAssertFalse(MeetingName.isValid("a/b"))
        XCTAssertFalse(MeetingName.isValid("a b"))
    }

    func testAcceptsSkillNames() {
        XCTAssertTrue(MeetingName.isValid("2026-11-03-standup"))
        XCTAssertTrue(MeetingName.isValid("a.b_c-1"))
    }

    func testDefaultNameUsesLocalDay() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        let date = cal.date(from: DateComponents(year: 2026, month: 11, day: 3))!
        XCTAssertEqual(
            MeetingName.defaultName(date: date, slug: "standup", timeZone: TimeZone(secondsFromGMT: 0)!),
            "2026-11-03-standup"
        )
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `swift test --filter MeetingNameTests`
Expected: FAIL because `MeetingCore` does not exist yet.

- [ ] **Step 3: Write the package and the implementation**

`Package.swift`:

```swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MeetingWindow",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "MeetingCore"),
        .executableTarget(name: "MeetingWindow", dependencies: ["MeetingCore"]),
        .testTarget(name: "MeetingCoreTests", dependencies: ["MeetingCore"])
    ]
)
```

Create an empty `Sources/MeetingWindow/MeetingWindowApp.swift` with `import MeetingCore` so the executable target typechecks. The real panel is Task 14.

`Sources/MeetingCore/MeetingName.swift`:

```swift
import Foundation

public enum MeetingName {
    public static func isValid(_ name: String) -> Bool {
        guard !name.isEmpty else { return false }
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_.")
        return name.unicodeScalars.allSatisfy { allowed.contains($0) }
    }

    public static func defaultName(date: Date, slug: String, timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        let clean = slug.isEmpty ? "meeting" : slug
        return formatter.string(from: date) + "-" + clean
    }
}
```

The test passes a fixed offset of zero seconds so the calendar day does not follow the machine zone.

- [ ] **Step 4: Run the test to verify it passes**

Run: `swift test --filter MeetingNameTests`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git init
git add Package.swift Sources Tests
git commit -m "feat: validate meeting names"
```

### Task 2: Start command

**Files:**
- Create: `Sources/MeetingCore/StartCommand.swift`
- Test: `Tests/MeetingCoreTests/StartCommandTests.swift`

**Interfaces:**
- Consumes: nothing
- Produces: `StartCommand.argv() -> [String]`, `StartCommand.workingDirectory`

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import MeetingCore

final class StartCommandTests: XCTestCase {
    func testMicAndLangOnly() {
        let cmd = StartCommand(
            python: "python3",
            script: "/skill/scripts/meeting.py",
            workingDirectory: "/repo",
            name: "2026-11-03-standup",
            device: "default",
            lang: "th",
            tapApp: nil,
            replayWav: nil
        )
        XCTAssertEqual(cmd.workingDirectory, "/repo")
        XCTAssertEqual(cmd.argv(), [
            "python3", "/skill/scripts/meeting.py", "start", "2026-11-03-standup",
            "--device", "default", "--lang", "th"
        ])
        XCTAssertFalse(cmd.argv().contains("--screen"))
        XCTAssertFalse(cmd.argv().contains("--app"))
        XCTAssertEqual(cmd.argv().filter { $0 == "--device" }.count, 1)
    }

    func testTapAndReplay() {
        let cmd = StartCommand(
            python: "python3",
            script: "/skill/scripts/meeting.py",
            workingDirectory: "/repo",
            name: "replay",
            device: "default",
            lang: "en",
            tapApp: "zoom.us",
            replayWav: "/tmp/call.wav"
        )
        let args = cmd.argv()
        XCTAssertEqual(args.suffix(4), ["--tap-app", "zoom.us", "--replay", "/tmp/call.wav"])
        XCTAssertEqual(args.filter { $0 == "--device" }.count, 1)
    }
}
```

`suffix(4)` is not a real Array API. Assert with `XCTAssertEqual(Array(args.suffix(4)), ["--tap-app", "zoom.us", "--replay", "/tmp/call.wav"])`.

- [ ] **Step 2: Run the test to verify it fails**

Run: `swift test --filter StartCommandTests`
Expected: FAIL with `StartCommand` not found.

- [ ] **Step 3: Write the implementation**

```swift
import Foundation

public struct StartCommand: Equatable {
    public var python: String
    public var script: String
    public var workingDirectory: String
    public var name: String
    public var device: String
    public var lang: String
    public var tapApp: String?
    public var replayWav: String?

    public init(python: String, script: String, workingDirectory: String, name: String, device: String, lang: String, tapApp: String?, replayWav: String?) {
        self.python = python
        self.script = script
        self.workingDirectory = workingDirectory
        self.name = name
        self.device = device
        self.lang = lang
        self.tapApp = tapApp
        self.replayWav = replayWav
    }

    public func argv() -> [String] {
        var args = [python, script, "start", name, "--device", device, "--lang", lang]
        if let tapApp, !tapApp.isEmpty {
            args.append("--tap-app")
            args.append(tapApp)
        }
        if let replayWav, !replayWav.isEmpty {
            args.append("--replay")
            args.append(replayWav)
        }
        return args
    }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `swift test --filter StartCommandTests`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add Sources/MeetingCore/StartCommand.swift Tests/MeetingCoreTests/StartCommandTests.swift
git commit -m "feat: build meeting.py start argv"
```

### Task 3: Transcript parser

**Files:**
- Create: `Sources/MeetingCore/TranscriptLine.swift`
- Test: `Tests/MeetingCoreTests/TranscriptLineTests.swift`

**Interfaces:**
- Consumes: nothing
- Produces: `TranscriptKind`, `TranscriptLine.parse(_:) -> TranscriptLine?`, `TranscriptLine.callsModel`

- [ ] **Step 1: Write the failing test**

```swift
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
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `swift test --filter TranscriptLineTests`
Expected: FAIL with `TranscriptLine` not found.

- [ ] **Step 3: Write the implementation**

```swift
import Foundation

public enum TranscriptKind: Equatable {
    case speech
    case silence
    case promptEcho
    case end
}

public struct TranscriptLine: Equatable {
    public var stamp: String
    public var text: String
    public var kind: TranscriptKind

    public var callsModel: Bool { kind == .speech }

    public static func parse(_ raw: String) -> TranscriptLine? {
        let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if line == "[END]" {
            return TranscriptLine(stamp: "", text: "[END]", kind: .end)
        }
        guard line.first == "[", let close = line.firstIndex(of: "]") else { return nil }
        let stamp = String(line[line.index(after: line.startIndex)..<close])
        let text = line[line.index(after: close)...].trimmingCharacters(in: .whitespaces)
        if text == "(silence)" {
            return TranscriptLine(stamp: stamp, text: String(text), kind: .silence)
        }
        if text == "(silence — prompt echo)" {
            return TranscriptLine(stamp: stamp, text: String(text), kind: .promptEcho)
        }
        return TranscriptLine(stamp: stamp, text: String(text), kind: .speech)
    }
}
```

The prompt-echo comparison string uses the same em dash the recorder writes in `meeting.py` `clean()`.

- [ ] **Step 4: Run the test to verify it passes**

Run: `swift test --filter TranscriptLineTests`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add Sources/MeetingCore/TranscriptLine.swift Tests/MeetingCoreTests/TranscriptLineTests.swift
git commit -m "feat: parse live transcript lines"
```

### Task 4: Turn queue

**Files:**
- Create: `Sources/MeetingCore/TurnQueue.swift`
- Test: `Tests/MeetingCoreTests/TurnQueueTests.swift`

**Interfaces:**
- Consumes: `TranscriptLine`
- Produces: `PendingTurn`, `TurnQueue.pushSpeech`, `TurnQueue.pushQuestion`, `TurnQueue.takeNext`, `TurnQueue.finish`, `TurnQueue.busy`

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import MeetingCore

final class TurnQueueTests: XCTestCase {
    func testQuestionJumpsAheadOfQueuedSpeech() {
        var queue = TurnQueue()
        let first = TranscriptLine.parse("[10:00:00] one")!
        let second = TranscriptLine.parse("[10:00:20] two")!
        XCTAssertEqual(queue.takeNext(), .speech(SpeechBatch(lines: [first])))
        queue.pushSpeech(first)
        _ = queue.takeNext()
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
```

The test above pushes `first` twice. Use this body instead:

```swift
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
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `swift test --filter TurnQueueTests`
Expected: FAIL with `TurnQueue` not found.

- [ ] **Step 3: Write the implementation**

```swift
import Foundation

public struct SpeechBatch: Equatable {
    public var lines: [TranscriptLine]
    public init(lines: [TranscriptLine]) { self.lines = lines }
}

public enum PendingTurn: Equatable {
    case question(String)
    case speech(SpeechBatch)
}

public struct TurnQueue {
    public private(set) var busy = false
    private var questions: [String] = []
    private var speech: [TranscriptLine] = []

    public init() {}

    public mutating func pushSpeech(_ line: TranscriptLine) {
        guard line.kind == .speech else { return }
        speech.append(line)
    }

    public mutating func pushQuestion(_ text: String) {
        questions.append(text)
    }

    public mutating func takeNext() -> PendingTurn? {
        guard !busy else { return nil }
        if !questions.isEmpty {
            busy = true
            return .question(questions.removeFirst())
        }
        if !speech.isEmpty {
            busy = true
            let batch = speech
            speech = []
            return .speech(SpeechBatch(lines: batch))
        }
        return nil
    }

    public mutating func finish() {
        busy = false
    }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `swift test --filter TurnQueueTests`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add Sources/MeetingCore/TurnQueue.swift Tests/MeetingCoreTests/TurnQueueTests.swift
git commit -m "feat: queue one secretary turn at a time"
```

### Task 5: Live notes

**Files:**
- Create: `Sources/MeetingCore/LiveNotes.swift`
- Test: `Tests/MeetingCoreTests/LiveNotesTests.swift`

**Interfaces:**
- Consumes: nothing
- Produces: `LiveNotes.entries(from:stamp:) -> [String]`

- [ ] **Step 1: Write the failing test**

```swift
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
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `swift test --filter LiveNotesTests`
Expected: FAIL with `LiveNotes` not found.

- [ ] **Step 3: Write the implementation**

```swift
import Foundation

public enum LiveNotes {
    public static let markers = ["❓", "⚠️", "✅", "📌", "📎", "🔎"]

    public static func entries(from reply: String, stamp: String) -> [String] {
        reply.split(separator: "\n", omittingEmptySubsequences: false).compactMap { raw in
            let line = String(raw).trimmingCharacters(in: .whitespaces)
            guard markers.contains(where: { line.hasPrefix($0) }) else { return nil }
            return "- [" + stamp + "] " + line
        }
    }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `swift test --filter LiveNotesTests`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add Sources/MeetingCore/LiveNotes.swift Tests/MeetingCoreTests/LiveNotesTests.swift
git commit -m "feat: keep actionable secretary lines"
```

### Task 6: Summary filenames

**Files:**
- Create: `Sources/MeetingCore/SummaryNames.swift`
- Test: `Tests/MeetingCoreTests/SummaryNamesTests.swift`

**Interfaces:**
- Consumes: nothing
- Produces: `SummaryNames.next(existing:) -> String`

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import MeetingCore

final class SummaryNamesTests: XCTestCase {
    func testAdvancesVersions() {
        XCTAssertEqual(SummaryNames.next(existing: []), "summary.md")
        XCTAssertEqual(SummaryNames.next(existing: ["summary.md"]), "summary-v2.md")
        XCTAssertEqual(SummaryNames.next(existing: ["summary.md", "summary-v2.md"]), "summary-v3.md")
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `swift test --filter SummaryNamesTests`
Expected: FAIL with `SummaryNames` not found.

- [ ] **Step 3: Write the implementation**

```swift
import Foundation

public enum SummaryNames {
    public static func next(existing: [String]) -> String {
        if !existing.contains("summary.md") { return "summary.md" }
        var n = 2
        while existing.contains("summary-v" + String(n) + ".md") { n += 1 }
        return "summary-v" + String(n) + ".md"
    }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `swift test --filter SummaryNamesTests`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add Sources/MeetingCore/SummaryNames.swift Tests/MeetingCoreTests/SummaryNamesTests.swift
git commit -m "feat: version summary filenames"
```

### Task 7: Log classifier

**Files:**
- Create: `Sources/MeetingCore/LogStatus.swift`
- Test: `Tests/MeetingCoreTests/LogStatusTests.swift`

**Interfaces:**
- Consumes: nothing
- Produces: `RecorderProblem`, `LogStatus.classify(_:) -> RecorderProblem?`, `LogStatus.message(for:) -> String`

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import MeetingCore

final class LogStatusTests: XCTestCase {
    func testMapsRecorderLines() {
        XCTAssertEqual(LogStatus.classify("ERROR recorder exited by itself — check microphone permission"), .microphonePermission)
        XCTAssertEqual(LogStatus.classify("12:00:00 ERROR no audio for 40 s — capture stalled"), .captureStalled)
        XCTAssertEqual(LogStatus.classify("12:00:40 audio resumed"), .audioResumed)
        XCTAssertEqual(LogStatus.classify("meeting-capture: process tap failed, OSStatus 1"), .systemAudioPermission)
        XCTAssertEqual(LogStatus.classify("grant System Audio Recording permission"), .systemAudioPermission)
        XCTAssertEqual(LogStatus.classify("WARNING: no running app named (or with bundle id) --tap-app 'zoom.us'"), .tapAppMissing)
        XCTAssertEqual(LogStatus.classify("10:00:00 ERROR vad: boom"), .sliceMissed)
        XCTAssertEqual(LogStatus.classify("10:00:00 ERROR window: boom"), .sliceMissed)
        XCTAssertEqual(LogStatus.classify("ERROR chunk 00001.wav: bad"), .sliceMissed)
        XCTAssertNil(LogStatus.classify("meeting-capture: levels: mic=-20"))
    }

    func testMicrophoneCopy() {
        XCTAssertEqual(
            LogStatus.message(for: .microphonePermission),
            "Microphone permission. Recording has stopped, and audio from here on is not kept."
        )
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `swift test --filter LogStatusTests`
Expected: FAIL with `LogStatus` not found.

- [ ] **Step 3: Write the implementation**

```swift
import Foundation

public enum RecorderProblem: Equatable {
    case microphonePermission
    case captureStalled
    case audioResumed
    case systemAudioPermission
    case tapAppMissing
    case sliceMissed
}

public enum LogStatus {
    public static func classify(_ line: String) -> RecorderProblem? {
        if line.contains("ERROR recorder exited by itself") { return .microphonePermission }
        if line.contains("capture stalled") { return .captureStalled }
        if line.contains("audio resumed") { return .audioResumed }
        if line.contains("process tap failed") || line.contains("System Audio Recording") { return .systemAudioPermission }
        if line.contains("WARNING: no running app named") { return .tapAppMissing }
        if line.contains("ERROR vad") || line.contains("ERROR window") || line.contains("ERROR chunk") { return .sliceMissed }
        return nil
    }

    public static func message(for problem: RecorderProblem) -> String {
        switch problem {
        case .microphonePermission:
            return "Microphone permission. Recording has stopped, and audio from here on is not kept."
        case .captureStalled:
            return "Capture stalled."
        case .audioResumed:
            return "Audio resumed."
        case .systemAudioPermission:
            return "System Audio Recording permission is missing for the app or meeting-capture."
        case .tapAppMissing:
            return "That call app is not running. Mic only, and the helper keeps rescanning."
        case .sliceMissed:
            return "That slice was not transcribed. Recording continues."
        }
    }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `swift test --filter LogStatusTests`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add Sources/MeetingCore/LogStatus.swift Tests/MeetingCoreTests/LogStatusTests.swift
git commit -m "feat: map recorder log lines to status"
```

### Task 8: Context pack

**Files:**
- Create: `Sources/MeetingCore/ContextPack.swift`
- Test: `Tests/MeetingCoreTests/ContextPackTests.swift`

**Interfaces:**
- Consumes: nothing
- Produces: `ContextPack.cap` equals 3000, `ContextPack.build(files:) -> ContextPackResult`, `ContextFiles.paths(root:topicTerms:meetingVocab:skillVocab:) -> [URL]`

- [ ] **Step 1: Write the failing test**

```swift
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
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `swift test --filter ContextPackTests`
Expected: FAIL with `ContextPack` not found.

- [ ] **Step 3: Write the implementation**

```swift
import Foundation

public struct PackedFile: Equatable {
    public var path: String
    public var text: String
    public init(path: String, text: String) {
        self.path = path
        self.text = text
    }
}

public struct ContextPackResult: Equatable {
    public var text: String
    public var files: [String]
    public var cut: Bool
}

public enum ContextPack {
    public static let cap = 3000

    public static func build(files: [PackedFile]) -> ContextPackResult {
        var out = ""
        var used: [String] = []
        var cut = false
        let notice = "\n\nPack was cut at 3000 characters."
        for file in files {
            let block = "\n\n# " + file.path + "\n" + file.text
            if out.count + block.count > cap {
                cut = true
                break
            }
            out += block
            used.append(file.path)
        }
        if cut { out += notice }
        return ContextPackResult(text: out, files: used, cut: cut)
    }
}

public enum ContextFiles {
    public static func paths(root: URL, topicTerms: [String], meetingVocab: URL?, skillVocab: URL?) -> [URL] {
        let fm = FileManager.default
        var urls: [URL] = []
        for name in ["CLAUDE.md", "AGENTS.md", "README", "README.md"] {
            let url = root.appendingPathComponent(name)
            if fm.fileExists(atPath: url.path) { urls.append(url) }
        }
        if !topicTerms.isEmpty {
            for dir in [".planning", "plans", "docs"] {
                let base = root.appendingPathComponent(dir)
                guard let items = try? fm.contentsOfDirectory(at: base, includingPropertiesForKeys: nil) else { continue }
                for url in items.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                    let name = url.lastPathComponent
                    if topicTerms.contains(where: { name.contains($0) }) { urls.append(url) }
                }
            }
        }
        for extra in [skillVocab, root.appendingPathComponent(".claude/meeting-vocab.txt"), meetingVocab] {
            if let extra, fm.fileExists(atPath: extra.path) { urls.append(extra) }
        }
        return urls
    }
}
```

Vocab files are included as paths here. The caller reads them and passes terms only into `PackedFile.text`, not the raw file, before `ContextPack.build`. Task 14 does that read.

- [ ] **Step 4: Run the test to verify it passes**

Run: `swift test --filter ContextPackTests`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add Sources/MeetingCore/ContextPack.swift Tests/MeetingCoreTests/ContextPackTests.swift
git commit -m "feat: build a capped context pack"
```

### Task 9: Ollama note prompt and chat trim

**Files:**
- Create: `Sources/MeetingCore/NotePrompt.swift`
- Test: `Tests/MeetingCoreTests/NotePromptTests.swift`

**Interfaces:**
- Consumes: `TranscriptLine.parse`
- Produces: `NotePrompt.budget` equals 7000, `NotePrompt.ollama(pack:packFiles:template:transcript:) -> OllamaNote`, `OllamaChat.numCtx` equals 8192, `OllamaChat.fitting() -> [OllamaMessage]`

- [ ] **Step 1: Write the failing test**

```swift
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
        let total = fitted.reduce(0) { $0 + $1.content.count }
        XCTAssertLessThanOrEqual(total, 7000)
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `swift test --filter NotePromptTests`
Expected: FAIL with `NotePrompt` not found.

- [ ] **Step 3: Write the implementation**

```swift
import Foundation

public struct OllamaNote: Equatable {
    public var prompt: String
    public var shortened: Bool
}

public enum NotePrompt {
    public static let budget = 7000

    public static func ollama(pack: String, packFiles: [String], template: String, transcript: String) -> OllamaNote {
        let speech = transcript.split(separator: "\n").compactMap { raw -> String? in
            guard let line = TranscriptLine.parse(String(raw)), line.kind == .speech else { return nil }
            return "[" + line.stamp + "] " + line.text
        }
        var body = "Pack files: " + packFiles.joined(separator: ", ") + "\n" + pack + "\n" + template + "\n"
        var shortened = false
        let marker = "Transcript was shortened.\n"
        for line in speech {
            if body.count + line.count + 1 + marker.count > budget {
                shortened = true
                break
            }
            body += line + "\n"
        }
        if shortened { body += marker }
        return OllamaNote(prompt: body, shortened: shortened)
    }
}

public struct OllamaMessage: Equatable {
    public var role: String
    public var content: String
    public init(role: String, content: String) {
        self.role = role
        self.content = content
    }
}

public struct OllamaChat {
    public static let numCtx = 8192
    public static let budget = 7000
    public var messages: [OllamaMessage]

    public init(system: String) {
        messages = [OllamaMessage(role: "system", content: system)]
    }

    public mutating func add(user: String, assistant: String) {
        messages.append(OllamaMessage(role: "user", content: user))
        messages.append(OllamaMessage(role: "assistant", content: assistant))
    }

    public func fitting() -> [OllamaMessage] {
        guard let system = messages.first else { return [] }
        var kept: [OllamaMessage] = []
        var count = system.content.count
        for message in messages.dropFirst().reversed() {
            if count + message.content.count > Self.budget { break }
            kept.insert(message, at: 0)
            count += message.content.count
        }
        return [system] + kept
    }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `swift test --filter NotePromptTests`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add Sources/MeetingCore/NotePrompt.swift Tests/MeetingCoreTests/NotePromptTests.swift
git commit -m "feat: cap Ollama notes and chat"
```

### Task 10: Prompts and session requests

**Files:**
- Create: `Sources/MeetingCore/Prompts.swift`
- Create: `Sources/MeetingCore/Sessions.swift`
- Test: `Tests/MeetingCoreTests/SessionRequestTests.swift`

**Interfaces:**
- Consumes: `OllamaChat`, `OllamaMessage`
- Produces: `Prompts.live(project:) -> String`, `Prompts.noteTemplate`, `ClaudeLaunch.liveArgv(project:) -> [String]`, `ClaudeLaunch.noteArgv(project:sessionID:) -> [String]`, `AgyLaunch.liveArgv() -> [String]`, `AgyLaunch.noteArgv(sessionID:) -> [String]`, `CodexLaunch.execArgv(project:gitRepo:) -> [String]`, `CodexLaunch.resumeArgv(id:project:gitRepo:) -> [String]`, `OllamaLaunch.body(chat:) -> Data`, `SessionID.parse(from:) -> String?`

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import MeetingCore

final class SessionRequestTests: XCTestCase {
    func testClaudeLiveIsReadOnly() {
        let args = ClaudeLaunch.liveArgv(project: "/repo")
        XCTAssertTrue(args.contains("--restricted"))
        XCTAssertTrue(args.contains("Read,Grep,Glob"))
        XCTAssertTrue(args.contains("Bash,Edit,Write"))
        XCTAssertFalse(args.contains("--dangerously-skip-permissions"))
        XCTAssertTrue(Prompts.live(project: "/repo").contains("/repo"))
        XCTAssertTrue(Prompts.live(project: "/repo").contains("🔎 queued"))
    }

    func testClaudeNoteAddsGhOnly() {
        let args = ClaudeLaunch.noteArgv(project: "/repo", sessionID: "sid")
        XCTAssertTrue(args.contains("--resume"))
        XCTAssertTrue(args.contains("sid"))
        XCTAssertTrue(args.contains("Read,Grep,Glob,Bash(gh *)"))
        XCTAssertTrue(args.contains("Edit,Write"))
        XCTAssertFalse(args.contains("--restricted"))
        XCTAssertFalse(args.joined(separator: " ").contains("bypass"))
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
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `swift test --filter SessionRequestTests`
Expected: FAIL with `ClaudeLaunch` not found.

- [ ] **Step 3: Write the implementation**

`Prompts.live(project:)` returns one string that includes the project path, the reply rows from the spec (❓ ⚠️ ✅ 📌 📎 · 🔎 queued), the ground-truth order, the 30 second rule, and the sentence "Read files inside the project folder only. No shell, no network, no edits." `Prompts.noteTemplate` contains the headings Summary, Decisions, Rules and figures learned, Action items, Waiting on others, Open questions, Corrections vs. what was said, and Proposed follow-ups. Empty sections say "none heard". It tells the model to return only the markdown, to tag claims `[doc: confirmed path:line]`, `[doc: contradicts path:line]`, or `[meeting only]`, to mark a single heard figure `(?)`, and to leave quotes as spoken.

`Sessions.swift` argv builders return exactly the flags the tests assert. `ClaudeLaunch.liveArgv` is:

```swift
["claude", "-p", "--input-format", "stream-json", "--output-format", "stream-json", "--permission-mode", "dontAsk", "--restricted", "--allowedTools", "Read,Grep,Glob", "--disallowedTools", "Bash,Edit,Write", "--system-prompt", Prompts.live(project: project)]
```

`ClaudeLaunch.noteArgv` uses `--resume`, the session id, `--allowedTools`, `Read,Grep,Glob,Bash(gh *)`, `--disallowedTools`, `Edit,Write`, and `--system-prompt` set to `Prompts.noteTemplate`. It does not pass `--restricted`.

`AgyLaunch.liveArgv` matches the test array. `AgyLaunch.noteArgv` is `["agy", "--print", "--mode", "plan", "--conversation", sessionID]`.

`CodexLaunch.execArgv` is `["codex", "exec", "-C", project, "--sandbox", "read-only"]` plus `--skip-git-repo-check` only when `gitRepo` is false. `resumeArgv` inserts `resume` and the id after `exec`.

`OllamaLaunch.body` JSON-encodes `model`, `messages` from `chat.fitting()`, `stream: false`, and `options.num_ctx` of `OllamaChat.numCtx`.

`SessionID.parse` decodes a JSON object and returns a string value for `session_id`, `sessionId`, or `conversation`. If that fails, it returns the first UUID in the line.

- [ ] **Step 4: Run the test to verify it passes**

Run: `swift test --filter SessionRequestTests`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add Sources/MeetingCore/Prompts.swift Sources/MeetingCore/Sessions.swift Tests/MeetingCoreTests/SessionRequestTests.swift
git commit -m "feat: build read-only session requests"
```

### Task 11: Meeting loop

**Files:**
- Create: `Sources/MeetingCore/MeetingLoop.swift`
- Test: `Tests/MeetingCoreTests/MeetingLoopTests.swift`

**Interfaces:**
- Consumes: `TurnQueue`, `TranscriptLine`, `LiveNotes`, `PendingTurn`
- Produces: `SecretarySession`, `FakeSession`, `MeetingLoop.onSpeech`, `MeetingLoop.onQuestion`, `MeetingLoop.notes`, `MeetingLoop.status`, `MeetingLoop.tailStopped`, `TurnWatch.watch(started:now:finished:) -> TurnWatch`

- [ ] **Step 1: Write the failing test**

```swift
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
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `swift test --filter MeetingLoopTests`
Expected: FAIL with `MeetingLoop` not found.

- [ ] **Step 3: Write the implementation**

```swift
import Foundation

public protocol SecretarySession: AnyObject {
    var sessionID: String? { get }
    func send(_ prompt: String) throws -> String
    func close()
}

public enum SessionError: Error { case dead }

public final class FakeSession: SecretarySession {
    public var sessionID: String? = "fake"
    public var prompts: [String] = []
    public var reply: String
    public var fail = false
    public init(reply: String) { self.reply = reply }
    public func send(_ prompt: String) throws -> String {
        prompts.append(prompt)
        if fail { throw SessionError.dead }
        return reply
    }
    public func close() {}
}

public enum TurnWatch: Equatable {
    case running
    case waiting
    case done

    public static func watch(started: Date, now: Date, finished: Bool) -> TurnWatch {
        if finished { return .done }
        if now.timeIntervalSince(started) >= 30 { return .waiting }
        return .running
    }
}

public final class MeetingLoop {
    public var notes = ""
    public var status = ""
    public var tailStopped = false
    private var queue = TurnQueue()
    private let session: SecretarySession

    public init(session: SecretarySession) { self.session = session }

    public func onSpeech(_ line: TranscriptLine) {
        queue.pushSpeech(line)
        pump()
    }

    public func onQuestion(_ text: String) {
        queue.pushQuestion(text)
        pump()
    }

    private func pump() {
        guard let turn = queue.takeNext() else { return }
        let prompt: String
        let stamp: String
        switch turn {
        case .question(let text):
            prompt = text
            stamp = ""
        case .speech(let batch):
            prompt = batch.lines.map { "[" + $0.stamp + "] " + $0.text }.joined(separator: "\n")
            stamp = batch.lines.last?.stamp ?? ""
        }
        do {
            let reply = try session.send(prompt)
            let entries = LiveNotes.entries(from: reply, stamp: stamp)
            if !entries.isEmpty { notes += entries.joined(separator: "\n") + "\n" }
            queue.finish()
            pump()
        } catch {
            status = "backend dead"
            queue.finish()
        }
    }
}
```

`TurnWatch.waiting` is the UI rule. While the watch is `.waiting` or `.running`, the caller does not call `onSpeech` into a second send. `MeetingModel` in Task 14 keeps `queue.busy` true until `.done`. The loop above is synchronous, so the 30 second rule is the watch function the model consults.

- [ ] **Step 4: Run the test to verify it passes**

Run: `swift test --filter MeetingLoopTests`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add Sources/MeetingCore/MeetingLoop.swift Tests/MeetingCoreTests/MeetingLoopTests.swift
git commit -m "feat: log secretary replies from a fake session"
```

### Task 12: Recorder client

**Files:**
- Create: `Sources/MeetingCore/RecorderClient.swift`
- Test: `Tests/MeetingCoreTests/RecorderClientTests.swift`

**Interfaces:**
- Consumes: nothing
- Produces: `RecorderClient.parseStatus(_:) -> RecorderStatus`, `RecorderClient.parseStart(_:) -> StartInfo?`, `RecorderClient.parseStop(_:) -> StopInfo?`, `StopGate.decide(first:second:confirmedKill:) -> StopAction`

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import MeetingCore

final class RecorderClientTests: XCTestCase {
    func testStatusText() {
        XCTAssertEqual(RecorderClient.parseStatus("no active meeting").recording, false)
        let live = RecorderClient.parseStatus("standup pid=42 alive=true chunks=1 lines=2\n[10:00:00] hi")
        XCTAssertTrue(live.recording)
        XCTAssertEqual(live.name, "standup")
        XCTAssertEqual(live.pid, 42)
    }

    func testStartAndStopJSON() {
        let start = RecorderClient.parseStart("{\"name\":\"standup\",\"dir\":\"/repo/.meetings/standup\",\"pid\":9,\"transcript\":\"/t.md\",\"log\":\"/r.log\"}")
        XCTAssertEqual(start?.transcript, "/t.md")
        XCTAssertEqual(start?.log, "/r.log")
        XCTAssertEqual(start?.pid, 9)
        let stop = RecorderClient.parseStop("{\"name\":\"standup\",\"dir\":\"/repo/.meetings/standup\",\"stopped\":false,\"pid\":9}")
        XCTAssertEqual(stop?.stopped, false)
        XCTAssertEqual(stop?.pid, 9)
    }

    func testKillOnlyAfterSecondFailureAndConfirm() {
        let running = StopInfo(stopped: false, pid: 9, name: "standup", dir: "/repo/.meetings/standup")
        let done = StopInfo(stopped: true, pid: nil, name: "standup", dir: "/repo/.meetings/standup")
        XCTAssertEqual(StopGate.decide(first: running, second: nil, confirmedKill: false), .retry)
        XCTAssertEqual(StopGate.decide(first: running, second: running, confirmedKill: false), .askKill(pid: 9))
        XCTAssertEqual(StopGate.decide(first: running, second: running, confirmedKill: true), .kill(pid: 9))
        XCTAssertEqual(StopGate.decide(first: done, second: nil, confirmedKill: false), .final)
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `swift test --filter RecorderClientTests`
Expected: FAIL with `RecorderClient` not found.

- [ ] **Step 3: Write the implementation**

```swift
public struct RecorderStatus: Equatable {
    public var recording: Bool
    public var name: String?
    public var pid: Int?
}

public struct StartInfo: Equatable {
    public var transcript: String
    public var log: String
    public var pid: Int
}

public struct StopInfo: Equatable {
    public var stopped: Bool
    public var pid: Int?
    public var name: String
    public var dir: String
}

public enum RecorderClient {
    public static func parseStatus(_ stdout: String) -> RecorderStatus {
        let first = stdout.split(separator: "\n").first.map(String.init) ?? ""
        if first == "no active meeting" {
            return RecorderStatus(recording: false, name: nil, pid: nil)
        }
        let parts = first.split(separator: " ").map(String.init)
        let name = parts.first
        func field(_ key: String) -> String? {
            parts.first { $0.hasPrefix(key) }?.dropFirst(key.count).description
        }
        return RecorderStatus(
            recording: field("alive=") == "true",
            name: name,
            pid: Int(field("pid=") ?? "")
        )
    }

    public static func parseStart(_ stdout: String) -> StartInfo? {
        guard let obj = json(stdout),
              let transcript = obj["transcript"] as? String,
              let log = obj["log"] as? String,
              let pid = obj["pid"] as? Int else { return nil }
        return StartInfo(transcript: transcript, log: log, pid: pid)
    }

    public static func parseStop(_ stdout: String) -> StopInfo? {
        guard let obj = json(stdout),
              let stopped = obj["stopped"] as? Bool,
              let name = obj["name"] as? String,
              let dir = obj["dir"] as? String else { return nil }
        return StopInfo(stopped: stopped, pid: obj["pid"] as? Int, name: name, dir: dir)
    }

    private static func json(_ stdout: String) -> [String: Any]? {
        guard let data = stdout.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }
}

public enum StopAction: Equatable {
    case final
    case retry
    case askKill(pid: Int)
    case kill(pid: Int)
}

public enum StopGate {
    public static func decide(first: StopInfo, second: StopInfo?, confirmedKill: Bool) -> StopAction {
        if first.stopped { return .final }
        guard let second else { return .retry }
        if second.stopped { return .final }
        let pid = second.pid ?? first.pid ?? 0
        return confirmedKill ? .kill(pid: pid) : .askKill(pid: pid)
    }
}
```

`meeting.py final` runs only after an action of `.final`. After `.kill`, the app runs `kill <pid>` and then `meeting.py stop` once more, and runs `final` only when that stop parses `stopped: true`.

- [ ] **Step 4: Run the test to verify it passes**

Run: `swift test --filter RecorderClientTests`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add Sources/MeetingCore/RecorderClient.swift Tests/MeetingCoreTests/RecorderClientTests.swift
git commit -m "feat: parse recorder status start and stop"
```

### Task 13: Start gate, attach, and past meetings

**Files:**
- Create: `Sources/MeetingCore/StartGate.swift`
- Test: `Tests/MeetingCoreTests/StartGateTests.swift`

**Interfaces:**
- Consumes: `MeetingName`, `TranscriptLine`
- Produces: `StartGate.canStart`, `RecognizerCheck.ready`, `BackendCheck.ready(for:)`, `AttachBrief.prompt(notes:recent:) -> String`, `PastMeetings.newestUnnoted(root:) -> URL?`, `PrivacyNotice.text(for:) -> String`

- [ ] **Step 1: Write the failing test**

```swift
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
    }

    func testOllamaNeedsTheModelAndClaudeNeedsAPing() {
        XCTAssertFalse(BackendCheck(onPath: true, ollamaUp: false, hasModel: false, pingOK: true).ready(for: .ollama))
        XCTAssertTrue(BackendCheck(onPath: true, ollamaUp: true, hasModel: true, pingOK: false).ready(for: .ollama))
        XCTAssertFalse(BackendCheck(onPath: true, ollamaUp: false, hasModel: false, pingOK: false).ready(for: .claude))
        XCTAssertTrue(BackendCheck(onPath: true, ollamaUp: false, hasModel: false, pingOK: true).ready(for: .claude))
    }

    func testAttachUsesNotesAndTheLast20Lines() {
        let lines = (1...25).map { TranscriptLine(stamp: "10:00:\($0)", text: "n\($0)", kind: .speech) }
        let prompt = AttachBrief.prompt(notes: "- [10:00:01] 📌 a", recent: lines)
        XCTAssertTrue(prompt.contains("📌 a"))
        XCTAssertFalse(prompt.contains("n1\n") || prompt.hasPrefix("n1"))
        XCTAssertTrue(prompt.contains("n6"))
        XCTAssertTrue(prompt.contains("n25"))
    }

    func testPrivacyLines() {
        XCTAssertEqual(PrivacyNotice.text(for: .ollama), "Transcript text stays on this Mac.")
        XCTAssertEqual(PrivacyNotice.text(for: .claude), "Transcript text leaves the Mac.")
        XCTAssertEqual(PrivacyNotice.text(for: .codex), "Transcript text leaves the Mac.")
        XCTAssertEqual(PrivacyNotice.text(for: .agy), "Transcript text leaves the Mac.")
    }
}
```

Add a temp-directory test: two meeting folders, only the older has `summary.md`, `PastMeetings.newestUnnoted` returns the newer folder. Write `meta.json` in both.

Fix the attach assertion. `n1` can appear inside later text only if we search the rendered lines. Build the prompt as numbered lines and assert the first speech line in the prompt is `n6` and the last is `n25`.

- [ ] **Step 2: Run the test to verify it fails**

Run: `swift test --filter StartGateTests`
Expected: FAIL with `StartGate` not found.

- [ ] **Step 3: Write the implementation**

```swift
public enum Backend: String, CaseIterable {
    case claude
    case codex
    case agy
    case ollama
}

public struct StartGate: Equatable {
    public var project: String
    public var name: String
    public var consent: Bool
    public var backendReady: Bool
    public var recognizerReady: Bool
    public var alreadyRecording: Bool
    public var nameTaken: Bool

    public var canStart: Bool {
        !project.isEmpty
            && MeetingName.isValid(name)
            && consent
            && backendReady
            && recognizerReady
            && !alreadyRecording
            && !nameTaken
    }
}

public struct BackendCheck: Equatable {
    public var onPath: Bool
    public var ollamaUp: Bool
    public var hasModel: Bool
    public var pingOK: Bool

    public func ready(for backend: Backend) -> Bool {
        guard onPath else { return false }
        if backend == .ollama { return ollamaUp && hasModel }
        return pingOK
    }
}
```

`AttachBrief.prompt` takes the last 20 `recent` lines whose `kind` is `.speech`, then prefixes `notes`. `PrivacyNotice.text` returns the two sentences in the test. `PastMeetings.newestUnnoted` lists child directories that contain `meta.json` and contain no file whose name starts with `summary` and ends with `.md`, and returns the one with the newest `meta.json` modification date.

`RecognizerCheck` is a struct of five Bools (`cli`, `model`, `vad`, `ffmpeg`, `swiftc`) with `ready` true only when all five are true. The app fills it by checking `transcribe-cli`, `Qwen3-ASR-1.7B-Q8_0.gguf`, and `silero-vad-v6.2-F32.gguf` under `TCPP_HOME` or `~/.local/share/transcribe.cpp`, plus `ffmpeg` and `swiftc` on `PATH`.

- [ ] **Step 4: Run the test to verify it passes**

Run: `swift test --filter StartGateTests`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add Sources/MeetingCore/StartGate.swift Tests/MeetingCoreTests/StartGateTests.swift
git commit -m "feat: gate start and build the attach brief"
```

### Task 14: Window model and SwiftUI panel

**Files:**
- Create: `Sources/MeetingCore/MeetingModel.swift`
- Modify: `Sources/MeetingWindow/MeetingWindowApp.swift`
- Test: `Tests/MeetingCoreTests/MeetingModelTests.swift`

**Interfaces:**
- Consumes: every type from Tasks 1 to 13
- Produces: `MeetingModel.canStart`, `MeetingModel.begin()`, `MeetingModel.ingest(transcriptLine:)`, `MeetingModel.ingest(logLine:)`, `MeetingModel.stop()`, `MeetingModel.confirmKill()`, `MeetingModel.attach()`, `MeetingModel.writeNote(markdown:liveOnly:)`, `MeetingModel.replayWav`

The model does not spawn processes. Tests pass a `RecorderIO` and a `SecretarySession`. The app target constructs real `Process` values in `MeetingWindowApp.swift` and calls the same methods.

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import MeetingCore

final class MeetingModelTests: XCTestCase {
    func testBeginWritesVocabAndShowsPrivacyBeforeAModelCall() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let model = MeetingModel(project: dir.path, session: FakeSession(reply: "· 10:00 quiet"))
        model.name = "2026-11-03-standup"
        model.consent = true
        model.backendReady = true
        model.recognizerReady = true
        model.topicTerms = "Friday\n# skip\n\nship"
        model.backend = .claude
        XCTAssertTrue(model.canStart)
        model.begin(recorder: FakeRecorder())
        let vocab = try String(contentsOfFile: dir.path + "/.meetings/2026-11-03-standup/vocab-extra.txt")
        XCTAssertEqual(vocab, "Friday\nship\n")
        XCTAssertEqual(model.privacy, "Transcript text leaves the Mac.")
        model.ingest(transcriptLine: "[10:00:00] (silence)")
        XCTAssertTrue((model.session as! FakeSession).prompts.isEmpty)
        XCTAssertEqual(model.status, "recording, waiting for the first line.")
    }

    func testStopWritesSummaryWithoutOverwriting() throws {
        let model = MeetingModel(project: "/repo", session: FakeSession(reply: "# Note\n\n## Decisions\nnone heard\n"))
        model.meetingDir = "/repo/.meetings/standup"
        model.phase = .noting
        model.writeNote(markdown: "# Note\n\n## Decisions\nnone heard\n", liveOnly: false)
        XCTAssertTrue(model.summaryPath.hasSuffix("summary.md"))
        model.writeNote(markdown: "# Note\n", liveOnly: true)
        XCTAssertTrue(model.summaryPath.hasSuffix("summary-v2.md"))
        XCTAssertTrue(model.readout.contains("live-only") || model.lastNoteHasLiveOnlyLine)
    }
}
```

`FakeRecorder` conforms to `RecorderIO` and records the argv it was given. `begin` must call it with a `StartCommand` whose argv has one `--device` and no `--screen`.

- [ ] **Step 2: Run the test to verify it fails**

Run: `swift test --filter MeetingModelTests`
Expected: FAIL with `MeetingModel` not found.

- [ ] **Step 3: Write the model and the panel**

`MeetingModel` is a final class, `@Observable` if the deployment SDK has it, otherwise `ObservableObject`. Fields match the start gate: `project`, `name`, `consent`, `backend`, `lang` default `"th"`, `tapApp`, `topicTerms`, `backendReady`, `recognizerReady`, `status`, `privacy`, `transcript`, `secretaryLines`, `phase`.

`begin` checks `canStart`. It writes `vocab-extra.txt` under `<project>/.meetings/<name>/` with blank lines and `#` comments removed. It sets `privacy` from `PrivacyNotice`. It sets status to `recording, waiting for the first line.` It calls `recorder.start` with `StartCommand`. It does not send a model prompt yet.

`ingest(transcriptLine:)` parses with `TranscriptLine.parse`. Speech is shown immediately and passed to `MeetingLoop.onSpeech` only when `TurnWatch` is `.done` for any previous turn. Silence is appended to the transcript as `quiet` and is not sent. `[END]` sets status to `Press Stop.`

`ingest(logLine:)` uses `LogStatus.classify`. `.audioResumed` clears a stalled status. Other problems set `status` to `LogStatus.message`. The raw line stays available for the panel to quote.

`stop` closes the live session, then uses `StopGate`. `confirmKill` moves the gate to `.kill`. `writeNote` chooses `SummaryNames.next` from files already in `meetingDir`, prefixes `Live-only transcript.\n` when `liveOnly` is true, writes the file, and fills `readout` with the path. It does not apply follow-ups.

`MeetingWindowApp.swift` is a SwiftUI `WindowGroup` scene with `.windowLevel(.floating)`. The form has the project path, name, backend picker, language, mic or mic-plus-call, the call-app field, the sentence `Google Meet inside Chrome taps all of Chrome's audio, not one tab.`, topic terms, the consent toggle, and Start. Start is disabled when `canStart` is false. A developer menu command `Replay a recording…` sets `replayWav` on the `StartCommand`. The panel shows transcript lines, secretary lines, the status, and Stop.

Remember the last backend and last project in `UserDefaults` keys `lastBackend` and `lastProject`.

- [ ] **Step 4: Run the test to verify it passes**

Run: `swift test --filter MeetingModelTests`
Expected: PASS

Also run: `swift test`
Expected: the whole MeetingCore suite PASS

- [ ] **Step 5: Commit**

```bash
git add Sources/MeetingCore/MeetingModel.swift Sources/MeetingWindow/MeetingWindowApp.swift Tests/MeetingCoreTests/MeetingModelTests.swift
git commit -m "feat: add the meeting window model and panel"
```

### Task 15: App bundle, setup, and the recorder test

**Files:**
- Create: `Info.plist`
- Create: `scripts/bundle-app.sh`
- Create: `Sources/MeetingCore/Setup.swift`
- Test: `Tests/MeetingCoreTests/SetupTests.swift`

**Interfaces:**
- Consumes: `RecognizerCheck`
- Produces: `Setup.commands(root:missingFfmpeg:missingSwiftc:) -> [String]`

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import MeetingCore

final class SetupTests: XCTestCase {
    func testCommandsNameTheRealInstallSteps() {
        let commands = Setup.commands(root: URL(fileURLWithPath: "/tmp/transcribe.cpp"), missingFfmpeg: true, missingSwiftc: true)
        let text = commands.joined(separator: "\n")
        XCTAssertTrue(text.contains("git clone https://github.com/handy-computer/transcribe.cpp"))
        XCTAssertTrue(text.contains("Qwen3-ASR-1.7B-Q8_0.gguf"))
        XCTAssertTrue(text.contains("silero-vad-v6.2-F32.gguf"))
        XCTAssertTrue(text.contains("brew install ffmpeg"))
        XCTAssertTrue(text.contains("xcode-select --install"))
        XCTAssertFalse(text.contains("meeting.py start"))
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `swift test --filter SetupTests`
Expected: FAIL with `Setup` not found.

- [ ] **Step 3: Write setup, the plist, and the bundle script**

`Setup.commands` returns the clone, cmake build, and two curl lines from `meeting.py` `preflight`, plus `brew install ffmpeg` and `xcode-select --install` when those flags are true. It does not include a `start` command. The panel shows a Setup button only when `RecognizerCheck.ready` is false, runs those commands, and does not start a meeting.

`Info.plist` sets `CFBundleName` to `Ada Note`, `NSMicrophoneUsageDescription` to `Ada Note records the microphone for the live transcript.`, and `NSAudioCaptureUsageDescription` to `Ada Note taps a call app so the other side of the call is transcribed.`

`scripts/bundle-app.sh` runs `swift build -c release --product MeetingWindow`, copies the binary into `Ada Note.app/Contents/MacOS/MeetingWindow`, and copies `Info.plist` to `Ada Note.app/Contents/Info.plist`.

Run the skill's own tests once:

```bash
python3 -m unittest test_meeting
```

Working directory: the meeting-secretary skill's `scripts` directory
Expected: PASS, and `git status` in that repo shows no changes.

Manual checks, not part of `swift test`:

- Replay a short wav from the developer menu with Ollama and confirm `summary.md` appears under `.meetings`.
- Replay once with one cloud backend.
- On a real call, `recorder.log` contains `meeting-capture: levels` with both mic and tap moving.
- Deny Microphone once and confirm the status quotes `ERROR recorder exited by itself`.

- [ ] **Step 4: Run the test to verify it passes**

Run: `swift test --filter SetupTests`
Expected: PASS

Run: `swift test`
Expected: PASS

Run: `python3 -m unittest test_meeting` in the skill `scripts` directory
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add Info.plist scripts/bundle-app.sh Sources/MeetingCore/Setup.swift Tests/MeetingCoreTests/SetupTests.swift
git commit -m "feat: bundle the app and show recognizer setup"
```

Do not commit anything under `noomz-claude-skills`.
