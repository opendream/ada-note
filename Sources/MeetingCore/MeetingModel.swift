import Foundation
import Observation

public protocol RecorderIO {
    func start(_ command: StartCommand)
}

public enum NoteReadout {
    public static func text(
        summaryPath: String,
        markdown: String,
        liveOnly: Bool,
        wavPath: String?,
        wavBytes: Int64?,
        githubChecked: Bool
    ) -> String {
        var lines = [summaryPath]
        if liveOnly { lines.append("live-only") }
        if !markdown.isEmpty {
            lines.append("Decisions: \(count(markdown, heading: "Decisions"))")
            lines.append("Action items: \(count(markdown, heading: "Action items"))")
            lines.append("Open questions: \(count(markdown, heading: "Open questions"))")
            for raw in markdown.split(separator: "\n", omittingEmptySubsequences: false) {
                let line = String(raw)
                if line.contains("contradicts") { lines.append(line) }
            }
        }
        if let wavPath, let wavBytes {
            lines.append(wavPath + " " + String(wavBytes) + " bytes")
        }
        if !githubChecked {
            lines.append("GitHub was not checked.")
        }
        return lines.joined(separator: "\n")
    }

    private static func count(_ markdown: String, heading: String) -> Int {
        let rows = markdown.split(separator: "\n", omittingEmptySubsequences: false).map {
            String($0).trimmingCharacters(in: .whitespaces)
        }
        let title = "## " + heading
        var active = false
        var total = 0
        for line in rows {
            if line.hasPrefix("## ") {
                if active { break }
                active = line == title
                continue
            }
            guard active, !line.isEmpty else { continue }
            if normalized(line).compare("none heard", options: .caseInsensitive) == .orderedSame { continue }
            total += 1
        }
        return total
    }

    private static func normalized(_ line: String) -> String {
        var body = line.trimmingCharacters(in: .whitespaces)
        while let first = body.first, first == "-" || first == "*" || first == " " {
            body.removeFirst()
            body = body.trimmingCharacters(in: .whitespaces)
        }
        if let dot = body.firstIndex(of: "."),
           !body[..<dot].isEmpty,
           body[..<dot].allSatisfy({ $0.isNumber }) {
            body = body[body.index(after: dot)...].trimmingCharacters(in: .whitespaces)
        }
        return body
    }
}

public enum CaptureMode: String, CaseIterable, Identifiable, Equatable {
    case mic = "Mic"
    case micPlusCall = "Mic plus call"
    public var id: String { rawValue }
}

@Observable
public final class MeetingModel {
    public static let recorderPython = "python3"
    public var recorderScript = RecorderPaths.script()

    public enum Phase: Equatable {
        case idle
        case recording
        case noting
        case finalReady
    }

    public var project: String
    public var name = ""
    public var consent = false
    public var backend: Backend = .claude
    public var lang = "th"
    public var tapApp = ""
    public var captureMode: CaptureMode = .mic
    public var topicTerms = ""
    public var backendReady = false
    public var recognizerReady = false
    public var alreadyRecording = false
    public var nameTaken = false
    public var device = "default"
    public var status = ""
    public var privacy = ""
    public var transcript: [String] = []
    public var secretaryLines: [String] = []
    public var phase: Phase = .idle
    public var meetingDir = ""
    public var summaryPath = ""
    public var readout = ""
    public var lastNoteHasLiveOnlyLine = false
    public var replayWav: String?
    public var rawLogLine = ""
    public let session: SecretarySession
    public private(set) var stopAction: StopAction?
    public private(set) var finalAllowed = false
    public private(set) var ownsRecording = false
    public private(set) var canRetryNote = false
    public private(set) var noteLiveOnly = false
    public var transcriptPath = ""
    public var logPath = ""
    public var unnotedPath = ""

    public var inputsFrozen: Bool {
        ownsRecording || canRetryNote || phase == .recording || phase == .noting || phase == .finalReady
    }

    public var canStop: Bool {
        ownsRecording && phase != .noting && phase != .finalReady
    }

    public var resolvedTranscriptPath: String {
        if !transcriptPath.isEmpty { return transcriptPath }
        guard !meetingDir.isEmpty else { return "" }
        return URL(fileURLWithPath: meetingDir).appendingPathComponent("transcript-live.md").path
    }

    public var resolvedLogPath: String {
        if !logPath.isEmpty { return logPath }
        guard !meetingDir.isEmpty else { return "" }
        return URL(fileURLWithPath: meetingDir).appendingPathComponent("recorder.log").path
    }

    /// Runs one secretary turn. Tests keep the default, which finishes before returning.
    /// The app replaces it so `session.send` leaves the main thread.
    @ObservationIgnored
    public var performTurn: (@escaping () -> Void) -> Void = { $0() }

    private let replyTap: ReplyTap
    private let loop: MeetingLoop
    private var recentLines: [TranscriptLine] = []
    private var rememberedSummaries: [String] = []
    private var rememberedDir = ""
    private var seenReplies = 0
    private var turnStarted: Date?
    private var turnFinished = true
    private var turnToken = 0
    private var stallLatched = false
    private var tapLatched = false
    private var statusBeforeStall = ""
    private var firstStopInfo: StopInfo?
    private var secondStopInfo: StopInfo?
    private var stopRequested = false
    private var killConfirmed = false
    private var rootProject = ""
    private var rootURL: URL?

    public init(project: String, session: SecretarySession) {
        self.project = project
        self.session = session
        let tap = ReplyTap(inner: session)
        self.replyTap = tap
        self.loop = MeetingLoop(session: tap)
    }

    public var canStart: Bool {
        let live = meetingFolderURL().appendingPathComponent("transcript-live.md")
        let taken = nameTaken || FileManager.default.fileExists(atPath: live.path)
        return StartGate(
            project: project,
            name: name,
            consent: consent,
            backendReady: backendReady,
            recognizerReady: recognizerReady,
            alreadyRecording: alreadyRecording || phase == .recording,
            nameTaken: taken
        ).canStart
    }

    public func begin(recorder: RecorderIO) {
        guard canStart else { return }
        let folder = meetingFolderURL()
        meetingDir = folder.path
        transcriptPath = folder.appendingPathComponent("transcript-live.md").path
        logPath = folder.appendingPathComponent("recorder.log").path
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let vocabText = filteredVocab(topicTerms)
            if !vocabText.isEmpty {
                let vocab = folder.appendingPathComponent("vocab-extra.txt")
                try vocabText.write(to: vocab, atomically: true, encoding: .utf8)
            }
        } catch {
            status = "Could not write vocab-extra.txt."
            return
        }
        privacy = PrivacyNotice.text(for: backend)
        status = "recording, waiting for the first line."
        phase = .recording
        alreadyRecording = true
        ownsRecording = true
        canRetryNote = false
        unnotedPath = ""
        transcript = []
        secretaryLines = []
        recentLines = []
        replyTap.wipe()
        seenReplies = 0
        turnToken += 1
        turnStarted = nil
        turnFinished = true
        loop.prepareForNewMeeting()
        session.reset()
        rawLogLine = ""
        stallLatched = false
        tapLatched = false
        killConfirmed = false
        stopRequested = false
        firstStopInfo = nil
        secondStopInfo = nil
        stopAction = nil
        finalAllowed = false
        recorder.start(startCommand())
    }

    public func ingest(transcriptLine raw: String) {
        ingest(transcriptLine: raw, send: true)
    }

    public func ingest(transcriptLine raw: String, send: Bool) {
        guard let line = TranscriptLine.parse(raw) else { return }
        recentLines.append(line)
        switch line.kind {
        case .silence, .promptEcho:
            transcript.append("quiet")
        case .end:
            transcript.append(raw)
            status = "Press Stop."
        case .speech:
            transcript.append(raw)
            guard send else { return }
            if status == "recording, waiting for the first line." {
                status = "recording"
            }
            forwardSpeech(line)
        }
    }

    public func ingest(logLine: String) {
        rawLogLine = logLine
        guard let problem = LogStatus.classify(logLine) else { return }
        switch problem {
        case .audioResumed:
            guard stallLatched else { return }
            stallLatched = false
            if status == LogStatus.message(for: .captureStalled) {
                status = statusBeforeStall
            }
        case .captureStalled:
            guard !stallLatched else { return }
            stallLatched = true
            statusBeforeStall = status
            status = LogStatus.message(for: .captureStalled)
        case .tapAppMissing:
            guard !tapLatched else { return }
            tapLatched = true
            status = LogStatus.message(for: .tapAppMissing)
        default:
            status = LogStatus.message(for: problem)
        }
    }

    public func stop() {
        firstStopInfo = nil
        secondStopInfo = nil
        stopAction = nil
        finalAllowed = false
        killConfirmed = false
        turnToken += 1
        stopRequested = true
        loop.discardQueued()
        session.close()
        stallLatched = false
        tapLatched = false
        refreshStopGate()
    }

    public func acceptStop(stdout: String, stderr: String = "") {
        let trimmed = stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        if let info = RecorderClient.parseStop(trimmed) {
            receiveStop(info)
            return
        }
        let blob = (stdout + "\n" + stderr).lowercased()
        if blob.contains("no active meeting") {
            receiveStop(StopInfo(stopped: true, pid: nil, name: name, dir: meetingDir))
            return
        }
        receiveStop(StopInfo(stopped: false, pid: nil, name: name, dir: meetingDir))
    }

    public func failStart(_ message: String) {
        guard phase == .recording, !stopRequested else { return }
        phase = .idle
        alreadyRecording = false
        ownsRecording = false
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        status = trimmed.isEmpty ? "Recorder did not start." : trimmed
    }

    public func adoptStart(_ info: StartInfo) {
        guard phase == .recording, !stopRequested else { return }
        if let dir = info.dir, !dir.isEmpty {
            meetingDir = dir
        }
        if !info.transcript.isEmpty {
            transcriptPath = info.transcript
            if meetingDir.isEmpty {
                meetingDir = URL(fileURLWithPath: info.transcript).deletingLastPathComponent().path
            }
        }
        if !info.log.isEmpty {
            logPath = info.log
        }
    }

    public func preparePastNote(at path: String) {
        let url = URL(fileURLWithPath: path, isDirectory: true)
        meetingDir = url.path
        transcriptPath = url.appendingPathComponent("transcript-live.md").path
        logPath = url.appendingPathComponent("recorder.log").path
        let folderName = url.lastPathComponent
        if MeetingName.isValid(folderName) {
            name = folderName
        }
        ownsRecording = true
        canRetryNote = false
        phase = .recording
        alreadyRecording = false
    }

    public func markNoteFailed(liveOnly: Bool) {
        noteLiveOnly = liveOnly
        canRetryNote = true
        ownsRecording = false
        phase = .idle
        status = "Note failed. Transcripts were kept."
        unnotedPath = ""
    }

    public func markNoteFinished() {
        canRetryNote = false
        ownsRecording = false
        phase = .idle
        refreshUnnoted()
    }

    public func beginNoteRetry() -> Bool {
        guard canRetryNote, !meetingDir.isEmpty else { return false }
        canRetryNote = false
        phase = .noting
        return true
    }

    public func refreshUnnoted() {
        guard phase == .idle, !ownsRecording, !canRetryNote, !alreadyRecording, !project.isEmpty else {
            unnotedPath = ""
            return
        }
        unnotedPath = PastMeetings.newestUnnoted(root: meetingsRoot())?.path ?? ""
    }

    public func ask(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !stopRequested else { return }
        let claim = loop.claimQuestion(trimmed)
        guard claim.ownsPump else { return }
        armTurn(reconnect: claim.reconnect)
    }

    public func refreshTurnWatch() {
        guard waitingOnTurn, !stopRequested, !stallLatched else { return }
        if status == "Press Stop." || status == "backend dead" || status == SessionError.tooLongStatus { return }
        status = "backend waiting"
    }

    public func receiveStop(_ info: StopInfo) {
        if !info.dir.isEmpty && (info.name.isEmpty || info.name == name || name.isEmpty) {
            meetingDir = info.dir
            transcriptPath = URL(fileURLWithPath: info.dir).appendingPathComponent("transcript-live.md").path
            logPath = URL(fileURLWithPath: info.dir).appendingPathComponent("recorder.log").path
            if name.isEmpty && !info.name.isEmpty {
                name = info.name
            }
        }
        if firstStopInfo == nil {
            firstStopInfo = info
        } else if secondStopInfo == nil {
            secondStopInfo = info
        }
        if stopRequested {
            refreshStopGate()
        }
    }

    public func confirmKill() {
        killConfirmed = true
        applyConfirmedKill()
    }

    public func attach() {
        phase = .recording
        alreadyRecording = true
        ownsRecording = true
        let prompt = brief(notes: loop.copyNotes())
        session.reset()
        let token = turnToken
        performTurn { [weak self] in
            guard let self else { return }
            do {
                let reply = try self.session.send(prompt)
                self.onMain(token: token) { self.appendSecretary(reply) }
            } catch {
                self.loop.markDead()
                self.onMain(token: token) { self.status = "backend dead" }
            }
        }
    }

    public func writeNote(markdown: String, liveOnly: Bool) {
        if meetingDir != rememberedDir {
            rememberedDir = meetingDir
            rememberedSummaries = []
        }
        var existing = rememberedSummaries
        for name in basenames(in: meetingDir) where !existing.contains(name) {
            existing.append(name)
        }
        let next = SummaryNames.next(existing: existing)
        rememberedSummaries.append(next)
        let path = URL(fileURLWithPath: meetingDir).appendingPathComponent(next).path
        summaryPath = path
        var body = markdown
        if liveOnly {
            body = "Live-only transcript.\n" + body
            lastNoteHasLiveOnlyLine = true
        }
        if directoryExists(meetingDir) {
            try? body.write(toFile: path, atomically: true, encoding: .utf8)
        }
        let wav = wavInfo()
        readout = NoteReadout.text(
            summaryPath: path,
            markdown: markdown,
            liveOnly: liveOnly,
            wavPath: wav?.path,
            wavBytes: wav?.bytes,
            githubChecked: backend == .claude
        )
        if liveOnly {
            lastNoteHasLiveOnlyLine = true
        }
    }

    private func startCommand() -> StartCommand {
        let tap: String? = captureMode == .micPlusCall ? tapApp : nil
        return StartCommand(
            python: Self.recorderPython,
            script: recorderScript,
            workingDirectory: project,
            name: name,
            device: device.isEmpty ? "default" : device,
            lang: lang.isEmpty ? "th" : lang,
            tapApp: tap,
            replayWav: replayWav
        )
    }

    private func forwardSpeech(_ line: TranscriptLine) {
        if stopRequested { return }
        let claim = loop.claimSpeech(line)
        if !claim.ownsPump {
            if waitingOnTurn { status = "backend waiting" }
            return
        }
        armTurn(reconnect: claim.reconnect)
    }

    private func armTurn(reconnect: Bool) {
        turnToken += 1
        let token = turnToken
        turnStarted = Date()
        turnFinished = false
        let lead = reconnect ? brief(notes: loop.copyNotes()) : ""
        performTurn { [weak self] in
            self?.deliver(token: token, lead: lead)
        }
    }

    private func deliver(token: Int, lead: String) {
        if stopRequested {
            loop.discardQueued()
            return
        }
        if !lead.isEmpty {
            do {
                try loop.sendLead(lead)
            } catch {
                onMain(token: token) {
                    self.turnFinished = true
                    self.pullReplies()
                    if !self.stopRequested {
                        self.status = self.loop.status == SessionError.tooLongStatus
                            ? SessionError.tooLongStatus
                            : "backend dead"
                    }
                    self.persistNotes()
                }
                return
            }
        }
        if stopRequested {
            loop.discardQueued()
            return
        }
        loop.drain()
        let dead = loop.status == "backend dead"
        let tooLong = loop.status == SessionError.tooLongStatus
        onMain(token: token) {
            self.turnFinished = true
            self.pullReplies()
            if tooLong {
                if !self.stopRequested { self.status = SessionError.tooLongStatus }
            } else if dead {
                if !self.stopRequested { self.status = "backend dead" }
            } else if self.status == "backend dead" || self.status == "backend waiting" || self.status == SessionError.tooLongStatus {
                self.status = "recording"
            }
            self.persistNotes()
        }
    }

    private func brief(notes: String) -> String {
        var notes = notes
        if notes.isEmpty, !meetingDir.isEmpty {
            let file = URL(fileURLWithPath: meetingDir).appendingPathComponent("live-notes.md").path
            if let text = try? String(contentsOfFile: file, encoding: .utf8) {
                notes = text
            }
        }
        return AttachBrief.prompt(notes: notes, recent: recentLines)
    }

    private var waitingOnTurn: Bool {
        guard let turnStarted, !turnFinished else { return false }
        return TurnWatch.watch(started: turnStarted, now: Date(), finished: false) == .waiting
    }

    private func onMain(token: Int, _ apply: @escaping () -> Void) {
        let work = {
            guard token == self.turnToken else { return }
            apply()
        }
        if Thread.isMainThread {
            work()
        } else {
            DispatchQueue.main.async(execute: work)
        }
    }

    private func pullReplies() {
        for reply in replyTap.takeNew(from: &seenReplies) {
            appendSecretary(reply)
        }
    }

    private func appendSecretary(_ reply: String) {
        for raw in reply.split(separator: "\n", omittingEmptySubsequences: false) {
            let text = String(raw).trimmingCharacters(in: .whitespaces)
            if !text.isEmpty {
                secretaryLines.append(text)
            }
        }
    }

    private func persistNotes() {
        guard directoryExists(meetingDir) else { return }
        let url = URL(fileURLWithPath: meetingDir).appendingPathComponent("live-notes.md")
        try? loop.copyNotes().write(to: url, atomically: true, encoding: .utf8)
    }

    private func refreshStopGate() {
        guard let first = firstStopInfo else { return }
        let action = StopGate.decide(first: first, second: secondStopInfo, confirmedKill: false)
        switch action {
        case .final:
            stopAction = .final
            finalAllowed = true
            alreadyRecording = false
            phase = .finalReady
        case .retry, .askKill:
            if killConfirmed {
                applyConfirmedKill()
            }
            if case .kill = stopAction { return }
            stopAction = action
            if case .askKill(let pid) = action, pid == 0 {
                phase = .idle
                alreadyRecording = false
                status = "Stop failed."
            }
        case .kill:
            applyConfirmedKill()
        }
    }

    private func applyConfirmedKill() {
        guard killConfirmed, let first = firstStopInfo else { return }
        let action = StopGate.decide(first: first, second: secondStopInfo, confirmedKill: true)
        guard case .kill(let pid) = action, pid != 0 else { return }
        stopAction = action
    }

    private func meetingsRoot() -> URL {
        if rootProject != project || rootURL == nil {
            rootProject = project
            rootURL = MeetingRoot.meetingsDirectory(picked: project)
        }
        return rootURL ?? URL(fileURLWithPath: project, isDirectory: true)
            .appendingPathComponent(".meetings", isDirectory: true)
    }

    private func meetingFolderURL() -> URL {
        meetingsRoot().appendingPathComponent(name, isDirectory: true)
    }

    private func wavInfo() -> (path: String, bytes: Int64)? {
        guard directoryExists(meetingDir) else { return nil }
        let url = URL(fileURLWithPath: meetingDir).appendingPathComponent("full.wav")
        guard FileManager.default.fileExists(atPath: url.path),
              let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attrs[.size] as? NSNumber else { return nil }
        return (url.path, size.int64Value)
    }

    private func filteredVocab(_ terms: String) -> String {
        let kept = terms.split(separator: "\n", omittingEmptySubsequences: false).compactMap { raw -> String? in
            let line = String(raw).trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.first == "#" { return nil }
            return line
        }
        if kept.isEmpty { return "" }
        return kept.joined(separator: "\n") + "\n"
    }

    private func basenames(in dir: String) -> [String] {
        guard directoryExists(dir) else { return [] }
        return (try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? []
    }

    private func directoryExists(_ path: String) -> Bool {
        guard !path.isEmpty else { return false }
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDir) && isDir.boolValue
    }
}

private final class ReplyTap: SecretarySession {
    let inner: SecretarySession
    private var replies: [String] = []
    private let lock = NSLock()
    init(inner: SecretarySession) { self.inner = inner }
    var sessionID: String? { inner.sessionID }
    func send(_ prompt: String) throws -> String {
        let reply = try inner.send(prompt)
        lock.lock()
        replies.append(reply)
        lock.unlock()
        return reply
    }
    func close() { inner.close() }
    func reset() { inner.reset() }
    func wipe() {
        lock.lock()
        replies.removeAll()
        lock.unlock()
    }
    func takeNew(from index: inout Int) -> [String] {
        lock.lock()
        defer { lock.unlock() }
        guard index < replies.count else { return [] }
        let fresh = Array(replies[index...])
        index = replies.count
        return fresh
    }
}
