import XCTest
@testable import MeetingCore

final class FakeRecorder: RecorderIO {
    var commands: [StartCommand] = []
    func start(_ command: StartCommand) {
        commands.append(command)
    }
}

final class MeetingModelTests: XCTestCase {
    func testBeginWritesVocabAndShowsPrivacyBeforeAModelCall() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let model = MeetingModel(project: dir.path, session: FakeSession(reply: "· 10:00 quiet"))
        XCTAssertFalse(model.canStart)
        model.name = "2026-11-03-standup"
        model.consent = true
        model.backendReady = true
        model.recognizerReady = true
        model.topicTerms = "Friday\n# skip\n\nship"
        model.backend = .claude
        XCTAssertTrue(model.canStart)
        let recorder = FakeRecorder()
        model.begin(recorder: recorder)
        let vocab = try String(contentsOfFile: dir.path + "/.meetings/2026-11-03-standup/vocab-extra.txt")
        XCTAssertEqual(vocab, "Friday\nship\n")
        XCTAssertEqual(model.privacy, "Transcript text leaves the Mac.")
        model.ingest(transcriptLine: "[10:00:00] (silence)")
        XCTAssertTrue((model.session as! FakeSession).prompts.isEmpty)
        XCTAssertEqual(model.status, "recording, waiting for the first line.")
        XCTAssertTrue(model.transcript.contains("quiet"))
        let argv = try XCTUnwrap(recorder.commands.first).argv()
        XCTAssertEqual(argv.filter { $0 == "--device" }.count, 1)
        XCTAssertFalse(argv.contains("--screen"))
        XCTAssertFalse(argv.contains("--app"))
        XCTAssertEqual(recorder.commands[0].python, "python3")
        XCTAssertEqual(recorder.commands[0].script, model.recorderScript)
        XCTAssertTrue(recorder.commands[0].script.hasSuffix("skills/meeting-secretary/scripts/meeting.py"))
        XCTAssertEqual(recorder.commands[0].device, "default")
        XCTAssertEqual(recorder.commands[0].lang, "th")
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
        XCTAssertTrue(model.readout.contains(model.summaryPath))
        XCTAssertFalse(FileManager.default.fileExists(atPath: "/repo"))
    }

    func testReplayWavIsCopiedOntoTheStartCommand() throws {
        let model = try readyModel()
        model.replayWav = "/tmp/call.wav"
        model.captureMode = .micPlusCall
        model.tapApp = "zoom.us"
        let recorder = FakeRecorder()
        model.begin(recorder: recorder)
        let argv = try XCTUnwrap(recorder.commands.first).argv()
        XCTAssertEqual(argv.filter { $0 == "--device" }.count, 1)
        XCTAssertFalse(argv.contains("--screen"))
        XCTAssertFalse(argv.contains("--app"))
        XCTAssertEqual(Array(argv.suffix(4)), ["--tap-app", "zoom.us", "--replay", "/tmp/call.wav"])
    }

    func testSpeechShowsImmediatelyAndSilenceDoesNotSend() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let session = FakeSession(reply: "📌 Sam → ship (Friday)\n· 10:00 quiet")
        let model = MeetingModel(project: dir.path, session: session)
        model.name = "2026-11-03-standup"
        model.consent = true
        model.backendReady = true
        model.recognizerReady = true
        model.begin(recorder: FakeRecorder())
        model.ingest(transcriptLine: "[10:00:01] ship it")
        XCTAssertTrue(model.transcript.contains { $0.contains("ship it") })
        XCTAssertEqual(session.prompts, ["[10:00:01] ship it"])
        XCTAssertTrue(model.secretaryLines.contains("📌 Sam → ship (Friday)"))
        XCTAssertTrue(model.secretaryLines.contains("· 10:00 quiet"))
        let notes = try String(contentsOfFile: dir.path + "/.meetings/2026-11-03-standup/live-notes.md")
        XCTAssertTrue(notes.contains("📌 Sam → ship (Friday)"))
        XCTAssertFalse(notes.contains("· 10:00 quiet"))
        model.ingest(transcriptLine: "[10:00:02] (silence)")
        model.ingest(transcriptLine: "[10:00:03] (silence — prompt echo)")
        XCTAssertEqual(session.prompts.count, 1)
        XCTAssertEqual(model.transcript.filter { $0 == "quiet" }.count, 2)
        model.ingest(transcriptLine: "[END]")
        XCTAssertEqual(model.status, "Press Stop.")
    }

    func testSecondSpeechWaitsUntilTheTurnIsDone() throws {
        let session = ReentrantSession()
        let model = MeetingModel(project: "/nowhere", session: session)
        session.model = model
        model.name = "2026-11-03-standup"
        model.consent = true
        model.backendReady = true
        model.recognizerReady = true
        model.ingest(transcriptLine: "[10:00:01] first")
        XCTAssertEqual(session.promptsDuringSend, 1)
        XCTAssertEqual(session.prompts, ["[10:00:01] first", "[10:00:02] during"])
        XCTAssertTrue(model.transcript.contains { $0.contains("during") })
    }

    func testLogStallClearsWithoutShowingAudioResumed() throws {
        let model = try readyModel()
        model.begin(recorder: FakeRecorder())
        let stalled = "12:00:00 ERROR no audio for 40 s — capture stalled"
        model.ingest(logLine: stalled)
        XCTAssertEqual(model.status, "Capture stalled.")
        XCTAssertEqual(model.rawLogLine, stalled)
        model.ingest(logLine: stalled)
        XCTAssertEqual(model.status, "Capture stalled.")
        model.ingest(logLine: "12:00:40 audio resumed")
        XCTAssertNotEqual(model.status, "Audio resumed.")
        XCTAssertFalse(model.status.contains("Audio resumed"))
        XCTAssertEqual(model.status, "recording, waiting for the first line.")
        let missing = "WARNING: no running app named (or with bundle id) --tap-app 'zoom.us'"
        model.ingest(logLine: missing)
        XCTAssertEqual(model.status, LogStatus.message(for: .tapAppMissing))
        model.ingest(logLine: missing)
        XCTAssertEqual(model.status, LogStatus.message(for: .tapAppMissing))
    }

    func testAttachSendsTheBriefAndDoesNotStartTheRecorder() throws {
        let session = FakeSession(reply: "· 10:01 caught up")
        let model = MeetingModel(project: "/repo", session: session)
        model.meetingDir = "/repo/.meetings/standup"
        model.ingest(transcriptLine: "[10:00:01] ship it")
        let recorder = FakeRecorder()
        model.attach()
        XCTAssertTrue(recorder.commands.isEmpty)
        XCTAssertEqual(session.prompts.count, 2)
        XCTAssertTrue(session.prompts.last?.contains("ship it") == true)
    }

    func testConfirmKillRunsOnlyAfterTheSecondStopAndSkipsPidZero() {
        let killed = MeetingModel(project: "/repo", session: FakeSession(reply: ""))
        killed.stop()
        killed.receiveStop(StopInfo(stopped: false, pid: 9, name: "standup", dir: "/repo/.meetings/standup"))
        killed.confirmKill()
        XCTAssertNotEqual(killed.stopAction, .kill(pid: 9))
        killed.receiveStop(StopInfo(stopped: false, pid: 9, name: "standup", dir: "/repo/.meetings/standup"))
        killed.confirmKill()
        XCTAssertEqual(killed.stopAction, .kill(pid: 9))

        let zero = MeetingModel(project: "/repo", session: FakeSession(reply: ""))
        zero.stop()
        zero.receiveStop(StopInfo(stopped: false, pid: 0, name: "standup", dir: "/repo/.meetings/standup"))
        zero.receiveStop(StopInfo(stopped: false, pid: 0, name: "standup", dir: "/repo/.meetings/standup"))
        zero.confirmKill()
        XCTAssertNotEqual(zero.stopAction, .kill(pid: 0))

        let done = MeetingModel(project: "/repo", session: FakeSession(reply: ""))
        done.stop()
        done.receiveStop(StopInfo(stopped: true, pid: 4, name: "standup", dir: "/repo/.meetings/standup"))
        XCTAssertEqual(done.stopAction, .final)
        XCTAssertTrue(done.finalAllowed)
        XCTAssertEqual(done.phase, .finalReady)
    }

    func testStopSlotsResetOnTheNextAttempt() {
        let model = MeetingModel(project: "/repo", session: FakeSession(reply: ""))
        model.name = "standup"
        model.meetingDir = "/repo/.meetings/standup"
        model.phase = .recording
        model.stop()
        let running = "{\"name\":\"standup\",\"dir\":\"/repo/.meetings/standup\",\"stopped\":false,\"pid\":9}"
        let stopped = "{\"name\":\"standup\",\"dir\":\"/repo/.meetings/standup\",\"stopped\":true}"
        model.acceptStop(stdout: running)
        model.acceptStop(stdout: running)
        XCTAssertEqual(model.stopAction, .askKill(pid: 9))
        XCTAssertFalse(model.finalAllowed)
        model.acceptStop(stdout: stopped)
        XCTAssertEqual(model.stopAction, .askKill(pid: 9))
        XCTAssertFalse(model.finalAllowed)
        model.stop()
        model.acceptStop(stdout: stopped)
        XCTAssertEqual(model.stopAction, .final)
        XCTAssertTrue(model.finalAllowed)
        XCTAssertEqual(model.phase, .finalReady)
    }

    func testWriteNoteWritesTheLiveOnlyLineWhenTheDirectoryExists() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let model = MeetingModel(project: "/unused", session: FakeSession(reply: ""))
        model.meetingDir = dir.path
        try "summary.md".write(toFile: dir.path + "/summary.md", atomically: true, encoding: .utf8)
        model.writeNote(markdown: "# Note\n", liveOnly: true)
        XCTAssertTrue(model.summaryPath.hasSuffix("summary-v2.md"))
        let body = try String(contentsOfFile: model.summaryPath)
        XCTAssertTrue(body.hasPrefix("Live-only transcript.\n"))
        XCTAssertTrue(model.lastNoteHasLiveOnlyLine)
        XCTAssertFalse(body.contains("follow-up applied"))
    }

    func testReadoutCountsContradictionsAudioAndSkipsGitHubForOllama() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let wav = dir.appendingPathComponent("full.wav")
        try Data([1, 2, 3, 4]).write(to: wav)
        let model = MeetingModel(project: "/unused", session: FakeSession(reply: ""))
        model.meetingDir = dir.path
        model.backend = .ollama
        let markdown = """
        ## Decisions
        Ship Friday

        ## Action items
        none heard

        ## Open questions
        Who owns it?

        ## Corrections vs. what was said
        [doc: contradicts README.md:3]
        """
        model.writeNote(markdown: markdown, liveOnly: false)
        XCTAssertTrue(model.readout.contains(model.summaryPath))
        XCTAssertTrue(model.readout.contains("Decisions: 1"))
        XCTAssertTrue(model.readout.contains("Action items: 0"))
        XCTAssertTrue(model.readout.contains("Open questions: 1"))
        XCTAssertTrue(model.readout.contains("contradicts"))
        XCTAssertTrue(model.readout.contains(wav.path))
        XCTAssertTrue(model.readout.contains("4 bytes"))
        XCTAssertTrue(model.readout.contains("GitHub was not checked."))
        model.backend = .claude
        model.writeNote(markdown: markdown, liveOnly: false)
        XCTAssertFalse(model.readout.contains("GitHub was not checked."))
        XCTAssertTrue(model.summaryPath.hasSuffix("summary-v2.md"))
    }

    func testSpeechDuringATurnIsOneBatchAndAQuestionGoesFirst() throws {
        let session = BatchSession()
        let model = MeetingModel(project: "/nowhere", session: session)
        session.model = model
        model.name = "2026-11-03-standup"
        model.consent = true
        model.backendReady = true
        model.recognizerReady = true
        model.ingest(transcriptLine: "[10:00:01] first")
        XCTAssertEqual(session.prompts, [
            "[10:00:01] first",
            "what did we ship",
            "[10:00:02] a\n[10:00:03] b"
        ])
    }

    func testDeadBackendReconnectsWithTheAttachBrief() throws {
        let session = FakeSession(reply: "📌 Sam → ship (Friday)")
        let model = MeetingModel(project: "/nowhere", session: session)
        session.fail = true
        model.ingest(transcriptLine: "[10:00:01] hello")
        XCTAssertEqual(model.status, "backend dead")
        XCTAssertEqual(session.prompts, ["[10:00:01] hello"])
        session.fail = false
        session.reply = "· 10:02 quiet"
        model.ingest(transcriptLine: "[10:00:02] next")
        XCTAssertEqual(session.prompts.count, 3)
        XCTAssertTrue(session.prompts[1].contains("[10:00:01] hello"))
        XCTAssertTrue(session.prompts[1].contains("[10:00:02] next"))
        XCTAssertEqual(session.prompts[2], "[10:00:02] next")
        XCTAssertEqual(model.status, "recording")
    }

    func testBeginClearsNotesAndResetsTheSession() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let inner = FakeSession(reply: "📌 Sam → ship (Friday)")
        let session = ResetWatch(inner: inner)
        let model = MeetingModel(project: dir.path, session: session)
        model.name = "2026-11-03-standup"
        model.consent = true
        model.backendReady = true
        model.recognizerReady = true
        model.begin(recorder: FakeRecorder())
        XCTAssertEqual(session.resets, 1)
        model.ingest(transcriptLine: "[10:00:01] ship it")
        let notes = dir.path + "/.meetings/2026-11-03-standup/live-notes.md"
        XCTAssertTrue(try String(contentsOfFile: notes).contains("📌"))
        model.phase = .idle
        model.alreadyRecording = false
        inner.reply = "· 10:02 quiet"
        model.begin(recorder: FakeRecorder())
        XCTAssertEqual(session.resets, 2)
        model.ingest(transcriptLine: "[10:00:02] next")
        let cleared = try String(contentsOfFile: notes)
        XCTAssertFalse(cleared.contains("📌"))
    }

    func testFailedStartRollsRecordingBack() throws {
        let model = try readyModel()
        model.begin(recorder: FakeRecorder())
        XCTAssertEqual(model.phase, .recording)
        XCTAssertFalse(model.canStart)
        model.failStart("missing: ffmpeg")
        XCTAssertEqual(model.phase, .idle)
        XCTAssertFalse(model.alreadyRecording)
        XCTAssertEqual(model.status, "missing: ffmpeg")
        XCTAssertTrue(model.canStart)
    }

    func testSpeechAfterStopDoesNotSend() {
        let session = StopSession()
        let model = MeetingModel(project: "/nowhere", session: session)
        session.model = model
        model.ingest(transcriptLine: "[10:00:01] first")
        XCTAssertEqual(session.prompts, ["[10:00:01] first"])
        XCTAssertTrue(model.transcript.contains { $0.contains("later") })
        model.ingest(transcriptLine: "[10:00:03] after stop")
        model.ask("still there")
        XCTAssertTrue(model.transcript.contains { $0.contains("after stop") })
        XCTAssertEqual(session.prompts, ["[10:00:01] first"])
    }

    func testUnparsedStopAdvancesTheGate() {
        let model = MeetingModel(project: "/repo", session: FakeSession(reply: ""))
        model.name = "standup"
        model.meetingDir = "/repo/.meetings/standup"
        model.phase = .recording
        model.alreadyRecording = true
        model.stop()
        model.acceptStop(stdout: "not json", stderr: "recorder pid 9 still running")
        XCTAssertEqual(model.stopAction, .retry)
        XCTAssertEqual(model.phase, .recording)
        model.acceptStop(stdout: "", stderr: "")
        XCTAssertEqual(model.stopAction, .askKill(pid: 0))
        XCTAssertEqual(model.phase, .idle)
        XCTAssertFalse(model.alreadyRecording)
        XCTAssertEqual(model.status, "Stop failed.")
        model.confirmKill()
        XCTAssertNotEqual(model.stopAction, .kill(pid: 0))

        let gone = MeetingModel(project: "/repo", session: FakeSession(reply: ""))
        gone.name = "standup"
        gone.meetingDir = "/repo/.meetings/standup"
        gone.phase = .recording
        gone.alreadyRecording = true
        gone.stop()
        gone.acceptStop(stdout: "", stderr: "no active meeting")
        XCTAssertEqual(gone.stopAction, .final)
        XCTAssertTrue(gone.finalAllowed)
        XCTAssertEqual(gone.phase, .finalReady)
        XCTAssertFalse(gone.alreadyRecording)
    }

    private func readyModel() throws -> MeetingModel {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let model = MeetingModel(project: dir.path, session: FakeSession(reply: "· 10:00 quiet"))
        model.name = "2026-11-03-standup"
        model.consent = true
        model.backendReady = true
        model.recognizerReady = true
        model.backend = .claude
        return model
    }
}

final class ReentrantSession: SecretarySession {
    var sessionID: String? = "re"
    var prompts: [String] = []
    var promptsDuringSend = 0
    weak var model: MeetingModel?
    func send(_ prompt: String) throws -> String {
        prompts.append(prompt)
        if prompts.count == 1 {
            model?.ingest(transcriptLine: "[10:00:02] during")
            promptsDuringSend = prompts.count
        }
        return "· 10:00 quiet"
    }
    func close() {}
    func reset() {}
}

final class BatchSession: SecretarySession {
    var sessionID: String? = "batch"
    var prompts: [String] = []
    weak var model: MeetingModel?
    func send(_ prompt: String) throws -> String {
        prompts.append(prompt)
        if prompts.count == 1 {
            model?.ask("what did we ship")
            model?.ingest(transcriptLine: "[10:00:02] a")
            model?.ingest(transcriptLine: "[10:00:03] b")
        }
        return "· 10:00 quiet"
    }
    func close() {}
    func reset() {}
}

final class StopSession: SecretarySession {
    var sessionID: String? = "stop"
    var prompts: [String] = []
    weak var model: MeetingModel?
    func send(_ prompt: String) throws -> String {
        prompts.append(prompt)
        if prompts.count == 1 {
            model?.ingest(transcriptLine: "[10:00:02] later")
            model?.stop()
        }
        return "· 10:00 quiet"
    }
    func close() {}
    func reset() {}
}

final class ResetWatch: SecretarySession {
    let inner: FakeSession
    var resets = 0
    init(inner: FakeSession) { self.inner = inner }
    var sessionID: String? { inner.sessionID }
    func send(_ prompt: String) throws -> String { try inner.send(prompt) }
    func close() { inner.close() }
    func reset() {
        resets += 1
        inner.reset()
    }
}
