import SwiftUI
import AppKit
import MeetingCore

@main
struct MeetingWindowApp: App {
    @NSApplicationDelegateAdaptor(MeetingAppDelegate.self) private var appDelegate
    @State private var model: MeetingModel

    init() {
        let savedProject = UserDefaults.standard.string(forKey: "lastProject") ?? ""
        let savedBackend = UserDefaults.standard.string(forKey: "lastBackend") ?? ""
        let session = AppSession()
        let model = MeetingModel(project: savedProject, session: session)
        session.model = model
        model.performTurn = { work in
            DispatchQueue.global(qos: .userInitiated).async(execute: work)
        }
        if let backend = Backend(rawValue: savedBackend) {
            model.backend = backend
        }
        if let device = ProcessInfo.processInfo.environment["MEETING_DEVICE"], !device.isEmpty {
            model.device = device
        }
        let recorderOverride = ProcessInfo.processInfo.environment["ADA_NOTE_RECORDER"] ?? ""
        if recorderOverride.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           let savedRecorder = UserDefaults.standard.string(forKey: "adaNoteRecorder"),
           !savedRecorder.isEmpty {
            model.recorderScript = savedRecorder
        }
        model.name = MeetingName.defaultName(date: Date(), slug: "meeting")
        UserDefaults.standard.set(model.project, forKey: "lastProject")
        UserDefaults.standard.set(model.backend.rawValue, forKey: "lastBackend")
        _model = State(initialValue: model)
        MeetingAppDelegate.model = model
    }

    var body: some Scene {
        WindowGroup("Ada Note") {
            MeetingPanel(model: model)
        }
        .commands {
            CommandMenu("Developer") {
                Button("Replay a recording…") {
                    let panel = NSOpenPanel()
                    panel.canChooseFiles = true
                    panel.canChooseDirectories = false
                    panel.allowsMultipleSelection = false
                    if panel.runModal() == .OK {
                        model.replayWav = panel.url?.path
                    }
                }
            }
        }
    }
}

final class MeetingAppDelegate: NSObject, NSApplicationDelegate {
    static var model: MeetingModel?

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let model = Self.model else { return .terminateNow }
        let recording = model.phase == .recording
        let noting = model.phase == .noting || model.phase == .finalReady
        guard recording || noting else { return .terminateNow }
        let alert = NSAlert()
        alert.messageText = recording ? "A meeting is still recording." : "A note is still being written."
        alert.informativeText = recording ? "Stop the recording before quitting?" : "Quit while the note is still running?"
        alert.addButton(withTitle: "Quit")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return .terminateCancel }
        guard recording else { return .terminateNow }
        let project = model.project
        model.stop()
        DispatchQueue.global(qos: .userInitiated).async {
            let outputs = project.isEmpty ? [] : MeetingPy.stopSequence(project: project)
            DispatchQueue.main.async {
                for item in outputs {
                    model.acceptStop(stdout: item.stdout, stderr: item.stderr)
                }
                MeetingFinish.writeIfFinal(model) {
                    NSApp.reply(toApplicationShouldTerminate: true)
                }
            }
        }
        return .terminateLater
    }
}

struct MeetingPanel: View {
    @Bindable var model: MeetingModel
    @State private var seenTranscript = 0
    @State private var seenLog = 0
    @State private var question = ""
    @State private var setupRunning = false

    var body: some View {
        Form {
            HStack {
                TextField("Project", text: $model.project)
                    .disabled(model.inputsFrozen)
                Button("Choose…") { chooseProject() }
                    .disabled(model.inputsFrozen)
            }
            TextField("Recorder", text: $model.recorderScript)
                .disabled(model.inputsFrozen)
                .onChange(of: model.recorderScript) { _, newValue in
                    UserDefaults.standard.set(newValue, forKey: "adaNoteRecorder")
                }
            if !FileManager.default.fileExists(atPath: model.recorderScript) {
                Text("That recorder script was not found. Point it at meeting.py from the meeting-secretary skill.")
            }
            TextField("Name", text: $model.name)
                .disabled(model.inputsFrozen)
            Picker("Backend", selection: $model.backend) {
                ForEach(Backend.allCases, id: \.self) { backend in
                    Text(backendTitle(backend)).tag(backend)
                }
            }
            .disabled(model.inputsFrozen)
            TextField("Language", text: $model.lang)
            Picker("Audio", selection: $model.captureMode) {
                ForEach(CaptureMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            TextField("Call app", text: $model.tapApp, prompt: Text("zoom.us or Microsoft Teams"))
            Text("Google Meet inside Chrome taps all of Chrome's audio, not one tab.")
            TextField("Topic terms", text: $model.topicTerms, axis: .vertical)
                .lineLimit(3...6)
            Toggle("Everyone in the meeting knows it is being recorded", isOn: $model.consent)
            if !model.recognizerReady {
                Button("Setup") { runRecognizerSetup() }
                    .disabled(setupRunning)
            }
            Button("Start") {
                seenTranscript = 0
                seenLog = 0
                model.begin(recorder: ProcessRecorder(model: model))
            }
            .disabled(!model.canStart || model.inputsFrozen)
            if model.alreadyRecording && model.phase != .recording {
                Button("Attach") { attachRecording() }
            }
            if !model.privacy.isEmpty {
                Text(model.privacy)
            }
            if let replay = model.replayWav, !replay.isEmpty {
                Text(replay)
            }
            Text("Transcript")
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(model.transcript.enumerated()), id: \.offset) { _, line in
                        Text(line).frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .frame(minHeight: 80)
            Text("Secretary")
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(model.secretaryLines.enumerated()), id: \.offset) { _, line in
                        Text(line).frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .frame(minHeight: 80)
            Text(model.status)
            if !model.rawLogLine.isEmpty {
                Text(model.rawLogLine)
            }
            if !model.readout.isEmpty {
                Text(model.readout)
            }
            HStack {
                TextField("Question", text: $question, prompt: Text("Ask about this meeting"))
                Button("Ask") {
                    let text = question
                    question = ""
                    model.ask(text)
                }
                .disabled(question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            Button("Stop") { userStop() }
                .disabled(!model.canStop)
            if model.canRetryNote {
                Button("Retry") { retryNote() }
            }
            if model.phase == .idle, !model.alreadyRecording, !model.ownsRecording, !model.canRetryNote,
               !model.unnotedPath.isEmpty {
                Button("Write note for \(URL(fileURLWithPath: model.unnotedPath).lastPathComponent)") {
                    notePastMeeting()
                }
            }
            if case .askKill(let pid) = model.stopAction {
                Text("Stop failed. Recorder pid \(pid).")
                Button("Kill recorder") {
                    model.confirmKill()
                    guard case .kill(let killPid) = model.stopAction, killPid != 0 else { return }
                    let project = model.project
                    MeetingPy.kill(pid: killPid)
                    model.stop()
                    guard !project.isEmpty else { return }
                    DispatchQueue.global(qos: .userInitiated).async {
                        let output = MeetingPy.capture(arguments: ["stop"], workingDirectory: project)
                        DispatchQueue.main.async {
                            model.acceptStop(stdout: output.stdout, stderr: output.stderr)
                            MeetingFinish.writeIfFinal(model, completion: nil)
                        }
                    }
                }
            }
        }
        .padding()
        .frame(minWidth: 480, minHeight: 640)
        .background(FloatingWindowLevel())
        .onAppear {
            MeetingAppDelegate.model = model
            refreshReadiness()
            RecorderStatusRefresh.apply(project: model.project, model: model)
            model.refreshUnnoted()
        }
        .onChange(of: model.project) { _, newValue in
            UserDefaults.standard.set(newValue, forKey: "lastProject")
            refreshReadiness()
            RecorderStatusRefresh.apply(project: newValue, model: model)
            model.refreshUnnoted()
        }
        .onChange(of: model.phase) { _, _ in
            model.refreshUnnoted()
        }
        .onChange(of: model.backend) { _, newValue in
            UserDefaults.standard.set(newValue.rawValue, forKey: "lastBackend")
            refreshReadiness()
        }
        .onReceive(Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()) { _ in
            model.refreshTurnWatch()
            pullNewLines()
        }
    }

    private func attachRecording() {
        seenTranscript = takeLines(path: model.resolvedTranscriptPath, log: false, seen: 0, send: false)
        seenLog = takeLines(path: model.resolvedLogPath, log: true, seen: 0, send: false)
        model.attach()
    }

    private func pullNewLines() {
        let following = model.phase == .recording || model.phase == .noting || model.phase == .finalReady
        guard following else { return }
        guard !model.resolvedTranscriptPath.isEmpty || !model.resolvedLogPath.isEmpty else { return }
        seenTranscript = takeLines(path: model.resolvedTranscriptPath, log: false, seen: seenTranscript, send: true)
        seenLog = takeLines(path: model.resolvedLogPath, log: true, seen: seenLog, send: true)
    }

    private func takeLines(path: String, log: Bool, seen: Int, send: Bool) -> Int {
        guard !path.isEmpty else { return seen }
        guard let text = try? String(contentsOfFile: path, encoding: .utf8), !text.isEmpty else { return seen }
        var lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        if !text.hasSuffix("\n") && !lines.isEmpty {
            lines.removeLast()
        }
        guard seen < lines.count else { return seen }
        for line in lines[seen...] where !line.isEmpty {
            if log {
                model.ingest(logLine: line)
            } else {
                model.ingest(transcriptLine: line, send: send)
            }
        }
        return lines.count
    }

    private func refreshReadiness() {
        let model = model
        let backend = model.backend
        let project = model.project
        DispatchQueue.global(qos: .userInitiated).async {
            let ready = Readiness.check(backend: backend, project: project)
            DispatchQueue.main.async {
                guard model.backend == backend else { return }
                model.recognizerReady = ready.recognizer
                model.backendReady = ready.backend
                let idle = model.phase == .idle && !model.ownsRecording && !model.canRetryNote
                guard idle else { return }
                if ready.signedOut {
                    model.status = "Backend is not signed in."
                } else if model.status == "Backend is not signed in." {
                    model.status = ""
                }
            }
        }
    }

    private func runRecognizerSetup() {
        guard !setupRunning else { return }
        setupRunning = true
        let root = Readiness.transcribeRoot()
        let commands = Setup.commands(
            root: root,
            missingFfmpeg: !Readiness.executable("ffmpeg"),
            missingSwiftc: !Readiness.executable("swiftc")
        )
        model.status = "Setting up the recognizer."
        DispatchQueue.global(qos: .userInitiated).async {
            let failure = Self.runInstall(commands, root: root)
            DispatchQueue.main.async {
                setupRunning = false
                if let failure {
                    model.status = "Setup stopped: " + failure
                } else {
                    model.status = "Recognizer setup finished."
                }
                refreshReadiness()
            }
        }
    }

    // Skip clone and an existing model file. Repeating them fails or re-downloads about 2 GB.
    // A failed tool line does not skip the other one. Clone, cmake, and curl wait until both have run.
    private static func runInstall(_ commands: [String], root: URL) -> String? {
        let model = root.appendingPathComponent("models/Qwen3-ASR-1.7B-Q8_0.gguf").path
        let vad = root.appendingPathComponent("models/silero-vad-v6.2-F32.gguf").path
        var toolFailure: String?
        for command in commands {
            if !isMissingTool(command), let toolFailure {
                return toolFailure
            }
            if command.hasPrefix("git clone ") {
                if FileManager.default.fileExists(atPath: root.path) { continue }
                try? FileManager.default.createDirectory(
                    at: root.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
            }
            if command.contains("Qwen3-ASR-1.7B-Q8_0.gguf"), FileManager.default.fileExists(atPath: model) {
                continue
            }
            if command.contains("silero-vad-v6.2-F32.gguf"), FileManager.default.fileExists(atPath: vad) {
                continue
            }
            if command.hasPrefix("curl ") {
                try? FileManager.default.createDirectory(
                    at: root.appendingPathComponent("models", isDirectory: true),
                    withIntermediateDirectories: true
                )
            }
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/sh")
            process.arguments = ["-c", command]
            var env = ProcessInfo.processInfo.environment
            env["PATH"] = Readiness.commandPath()
            process.environment = env
            do {
                try process.run()
            } catch {
                if isMissingTool(command) {
                    if toolFailure == nil { toolFailure = command }
                    continue
                }
                return command
            }
            process.waitUntilExit()
            if process.terminationStatus != 0 {
                if isMissingTool(command) {
                    if toolFailure == nil { toolFailure = command }
                    continue
                }
                return command
            }
        }
        return toolFailure
    }

    private static func isMissingTool(_ command: String) -> Bool {
        command == "xcode-select --install" || command == "brew install ffmpeg"
    }

    private func chooseProject() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            model.project = url.path
        }
    }

    private func retryNote() {
        let liveOnly = model.noteLiveOnly
        guard model.beginNoteRetry() else { return }
        DispatchQueue.global(qos: .userInitiated).async {
            var markdown: String?
            var failed = false
            if let session = model.session as? AppSession {
                do {
                    markdown = try session.requestNote(liveOnly: liveOnly)
                } catch {
                    failed = true
                }
            } else {
                failed = true
            }
            DispatchQueue.main.async {
                if failed {
                    model.markNoteFailed(liveOnly: liveOnly)
                } else if let markdown {
                    model.writeNote(markdown: markdown, liveOnly: liveOnly)
                    model.markNoteFinished()
                } else {
                    model.markNoteFailed(liveOnly: liveOnly)
                }
            }
        }
    }

    private func notePastMeeting() {
        let path = model.unnotedPath
        let project = model.project
        guard !path.isEmpty, !project.isEmpty else { return }
        guard model.phase == .idle, !model.alreadyRecording, !model.ownsRecording, !model.canRetryNote else { return }
        model.preparePastNote(at: path)
        model.stop()
        DispatchQueue.global(qos: .userInitiated).async {
            let outputs = MeetingPy.stopSequence(project: project)
            DispatchQueue.main.async {
                for item in outputs {
                    model.acceptStop(stdout: item.stdout, stderr: item.stderr)
                }
                MeetingFinish.writeIfFinal(model, completion: nil)
            }
        }
    }

    private func userStop() {
        guard model.canStop else { return }
        let project = model.project
        model.stop()
        guard !project.isEmpty else { return }
        DispatchQueue.global(qos: .userInitiated).async {
            let outputs = MeetingPy.stopSequence(project: project)
            DispatchQueue.main.async {
                for item in outputs {
                    model.acceptStop(stdout: item.stdout, stderr: item.stderr)
                }
                MeetingFinish.writeIfFinal(model, completion: nil)
            }
        }
    }

    private func backendTitle(_ backend: Backend) -> String {
        switch backend {
        case .claude: return "Claude Code"
        case .codex: return "Codex"
        case .agy: return "Antigravity"
        case .ollama: return "Ollama"
        }
    }
}

// windowLevel(_:) is macOS 15+. This package targets macOS 14.
private struct FloatingWindowLevel: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { view.window?.level = .floating }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { nsView.window?.level = .floating }
    }
}

private final class ProcessRecorder: RecorderIO {
    weak var model: MeetingModel?
    init(model: MeetingModel) { self.model = model }

    func start(_ command: StartCommand) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = command.argv()
        if !command.workingDirectory.isEmpty {
            process.currentDirectoryURL = URL(fileURLWithPath: command.workingDirectory)
        }
        let output = Pipe()
        let errors = Pipe()
        process.standardOutput = output
        process.standardError = errors
        do {
            try process.run()
        } catch {
            let model = self.model
            DispatchQueue.main.async {
                model?.failStart("Recorder did not start.")
            }
            return
        }
        let model = self.model
        DispatchQueue.global(qos: .userInitiated).async {
            let captured = MeetingPy.finish(process, output: output, errors: errors)
            let parsed = Self.startInfo(captured.stdout)
            DispatchQueue.main.async {
                guard let model else { return }
                if captured.status == 0, let parsed {
                    model.adoptStart(parsed)
                    return
                }
                let detail = (captured.stderr.isEmpty ? captured.stdout : captured.stderr)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                model.failStart(detail.isEmpty ? "Recorder did not start." : detail)
                RecorderStatusRefresh.apply(project: model.project, model: model)
            }
        }
    }

    private static func startInfo(_ stdout: String) -> StartInfo? {
        let trimmed = stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        if let info = RecorderClient.parseStart(trimmed) { return info }
        for line in stdout.split(separator: "\n") {
            if let info = RecorderClient.parseStart(String(line)) { return info }
        }
        return nil
    }
}

private enum RecorderStatusRefresh {
    static func apply(project: String, model: MeetingModel) {
        guard model.phase != .recording else { return }
        guard !project.isEmpty else {
            model.alreadyRecording = false
            return
        }
        DispatchQueue.global(qos: .userInitiated).async {
            let output = MeetingPy.capture(arguments: ["status"], workingDirectory: project)
            let parsed = RecorderClient.parseStatus(output.stdout)
            DispatchQueue.main.async {
                guard model.project == project, model.phase != .recording else { return }
                model.alreadyRecording = parsed.recording
                if parsed.recording, let name = parsed.name, !name.isEmpty {
                    model.name = name
                    let folder = MeetingRoot.meetingFolder(picked: project, name: name)
                    model.meetingDir = folder.path
                    model.transcriptPath = folder.appendingPathComponent("transcript-live.md").path
                    model.logPath = folder.appendingPathComponent("recorder.log").path
                }
            }
        }
    }
}

private struct Captured {
    var stdout: String
    var stderr: String
    var status: Int32
}

private enum MeetingPy {
    static func capture(arguments: [String], workingDirectory: String) -> Captured {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        let script = MeetingAppDelegate.model?.recorderScript ?? RecorderPaths.script()
        process.arguments = [MeetingModel.recorderPython, script] + arguments
        if !workingDirectory.isEmpty {
            process.currentDirectoryURL = URL(fileURLWithPath: workingDirectory)
        }
        let output = Pipe()
        let errors = Pipe()
        process.standardOutput = output
        process.standardError = errors
        do {
            try process.run()
        } catch {
            return Captured(stdout: "", stderr: "", status: 1)
        }
        return finish(process, output: output, errors: errors)
    }

    static func finish(_ process: Process, output: Pipe, errors: Pipe) -> Captured {
        let outHandle = output.fileHandleForReading
        let errHandle = errors.fileHandleForReading
        var outData = Data()
        var errData = Data()
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global(qos: .utility).async {
            outData = outHandle.readDataToEndOfFile()
            group.leave()
        }
        group.enter()
        DispatchQueue.global(qos: .utility).async {
            errData = errHandle.readDataToEndOfFile()
            group.leave()
        }
        process.waitUntilExit()
        group.wait()
        return Captured(
            stdout: String(data: outData, encoding: .utf8) ?? "",
            stderr: String(data: errData, encoding: .utf8) ?? "",
            status: process.terminationStatus
        )
    }

    static func stopSequence(project: String) -> [Captured] {
        let first = capture(arguments: ["stop"], workingDirectory: project)
        if stopSucceeded(first) { return [first] }
        let second = capture(arguments: ["stop"], workingDirectory: project)
        return [first, second]
    }

    static func stopSucceeded(_ item: Captured) -> Bool {
        let trimmed = item.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        if let info = RecorderClient.parseStop(trimmed), info.stopped { return true }
        let blob = (item.stdout + "\n" + item.stderr).lowercased()
        return blob.contains("no active meeting")
    }

    static func kill(pid: Int) {
        guard pid > 0 else { return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/kill")
        process.arguments = ["-TERM", String(pid)]
        do {
            try process.run()
        } catch {
            return
        }
        process.waitUntilExit()
    }
}

private enum MeetingFinish {
    static func writeIfFinal(_ model: MeetingModel, completion: (() -> Void)? = nil) {
        guard model.finalAllowed, model.phase == .finalReady, !model.name.isEmpty else {
            completion?()
            return
        }
        model.phase = .noting
        let name = model.name
        let project = model.project
        DispatchQueue.global(qos: .userInitiated).async {
            let final = MeetingPy.capture(arguments: ["final", name], workingDirectory: project)
            let liveOnly = final.status != 0
            var markdown: String?
            var failed = false
            if let session = model.session as? AppSession {
                do {
                    markdown = try session.requestNote(liveOnly: liveOnly)
                } catch {
                    failed = true
                }
            }
            DispatchQueue.main.async {
                if failed {
                    model.markNoteFailed(liveOnly: liveOnly)
                } else if let markdown {
                    model.writeNote(markdown: markdown, liveOnly: liveOnly)
                    model.markNoteFinished()
                } else {
                    model.markNoteFailed(liveOnly: liveOnly)
                }
                completion?()
            }
        }
    }
}

private enum Readiness {
    static func recognizerReady() -> Bool {
        let root = transcribeRoot()
        let fm = FileManager.default
        let check = RecognizerCheck(
            cli: fm.fileExists(atPath: root.appendingPathComponent("build/bin/transcribe-cli").path),
            model: fm.fileExists(atPath: root.appendingPathComponent("models/Qwen3-ASR-1.7B-Q8_0.gguf").path),
            vad: fm.fileExists(atPath: root.appendingPathComponent("models/silero-vad-v6.2-F32.gguf").path),
            ffmpeg: executable("ffmpeg"),
            swiftc: executable("swiftc")
        )
        return check.ready
    }

    struct Checked {
        var recognizer: Bool
        var backend: Bool
        var signedOut: Bool
    }

    static func check(backend: Backend, project: String) -> Checked {
        let recognizer = recognizerReady()
        let name: String
        switch backend {
        case .claude: name = "claude"
        case .codex: name = "codex"
        case .agy: name = "agy"
        case .ollama: name = "ollama"
        }
        let onPath = executable(name)
        var ollamaUp = false
        var hasModel = false
        if backend == .ollama, let tags = URL(string: "http://127.0.0.1:11434/api/tags"),
           let (code, body) = LocalHTTP.data(url: tags, method: "GET", body: nil, timeout: 2),
           code == 200 {
            ollamaUp = true
            hasModel = body.contains("qwen3.8")
        }
        let pingOK = backend == .ollama ? onPath : (onPath && pingCloud(backend, project: project))
        let ready = BackendCheck(onPath: onPath, ollamaUp: ollamaUp, hasModel: hasModel, pingOK: pingOK)
            .ready(for: backend)
        let signedOut = backend != .ollama && onPath && !pingOK
        return Checked(recognizer: recognizer, backend: ready, signedOut: signedOut)
    }

    // Read-only flags from the live launch. No bypass-permissions flag.
    private static func pingCloud(_ backend: Backend, project: String) -> Bool {
        let folder = project.isEmpty ? FileManager.default.homeDirectoryForCurrentUser.path : project
        let prompt = "Reply with ok"
        let argv: [String]
        let stream: Bool
        switch backend {
        case .claude:
            argv = ClaudeLaunch.liveArgv(project: folder)
            stream = true
        case .agy:
            argv = AgyLaunch.liveArgv()
            stream = true
        case .codex:
            let git = FileManager.default.fileExists(
                atPath: URL(fileURLWithPath: folder).appendingPathComponent(".git").path
            )
            argv = CodexLaunch.execArgv(project: folder, gitRepo: git)
            stream = false
        case .ollama:
            return false
        }
        let stdin: Data
        if stream {
            guard let line = streamLine(prompt) else { return false }
            stdin = line
        } else {
            stdin = Data((prompt + "\n").utf8)
        }
        guard let (status, stdout) = runLimited(argv: argv, project: folder, stdin: stdin, timeout: 25) else {
            return false
        }
        guard status == 0 else { return false }
        let range = NSRange(stdout.startIndex..<stdout.endIndex, in: stdout)
        guard let regex = try? NSRegularExpression(pattern: "\\bok\\b", options: .caseInsensitive) else {
            return false
        }
        return regex.firstMatch(in: stdout, options: [], range: range) != nil
    }

    private static func streamLine(_ prompt: String) -> Data? {
        let payload: [String: Any] = [
            "type": "user",
            "message": [
                "role": "user",
                "content": [["type": "text", "text": prompt]]
            ]
        ]
        guard var data = try? JSONSerialization.data(withJSONObject: payload) else { return nil }
        data.append(0x0A)
        return data
    }

    private static func runLimited(argv: [String], project: String, stdin: Data, timeout: TimeInterval) -> (Int32, String)? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = argv
        if !project.isEmpty, FileManager.default.fileExists(atPath: project) {
            process.currentDirectoryURL = URL(fileURLWithPath: project, isDirectory: true)
        }
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = commandPath()
        process.environment = env
        let input = Pipe()
        let output = Pipe()
        let errors = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = errors
        do {
            try process.run()
        } catch {
            return nil
        }
        let inHandle = input.fileHandleForWriting
        let outHandle = output.fileHandleForReading
        let errHandle = errors.fileHandleForReading
        var outData = Data()
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global(qos: .utility).async {
            outData = outHandle.readDataToEndOfFile()
            group.leave()
        }
        group.enter()
        DispatchQueue.global(qos: .utility).async {
            _ = errHandle.readDataToEndOfFile()
            group.leave()
        }
        group.enter()
        DispatchQueue.global(qos: .utility).async {
            try? inHandle.write(contentsOf: stdin)
            try? inHandle.close()
            group.leave()
        }
        let sem = DispatchSemaphore(value: 0)
        DispatchQueue.global(qos: .utility).async {
            process.waitUntilExit()
            sem.signal()
        }
        if sem.wait(timeout: .now() + timeout) == .timedOut {
            process.terminate()
            if sem.wait(timeout: .now() + 2) == .timedOut, process.isRunning {
                kill(process.processIdentifier, SIGKILL)
                _ = sem.wait(timeout: .now() + 2)
            }
        }
        group.wait()
        return (process.terminationStatus, String(data: outData, encoding: .utf8) ?? "")
    }

    static func transcribeRoot() -> URL {
        let env = ProcessInfo.processInfo.environment["TCPP_HOME"] ?? ""
        if !env.isEmpty { return URL(fileURLWithPath: env, isDirectory: true) }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".local/share/transcribe.cpp", isDirectory: true)
    }

    // Finder's PATH is /usr/bin:/bin:/usr/sbin:/sbin. The installer prepends the same
    // directories, so the gate and the command list see one search order.
    static let extraDirectories = ["/opt/homebrew/bin", "/usr/local/bin"]

    static func commandPath() -> String {
        let current = ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
        return extraDirectories.joined(separator: ":") + ":" + current
    }

    static func executable(_ name: String) -> Bool {
        let env = ProcessInfo.processInfo.environment["PATH"] ?? ""
        let envDirs = env.split(separator: ":").map(String.init).filter { !$0.isEmpty }
        for dir in extraDirectories + envDirs {
            let full = URL(fileURLWithPath: dir).appendingPathComponent(name).path
            if FileManager.default.isExecutableFile(atPath: full) { return true }
        }
        return false
    }
}

private enum LocalHTTP {
    private static let lock = NSLock()
    private static var task: URLSessionTask?

    static func cancel() {
        lock.lock()
        let current = task
        lock.unlock()
        current?.cancel()
    }

    static func data(url: URL, method: String, body: Data?, timeout: TimeInterval) -> (Int, String)? {
        guard url.host == "127.0.0.1" else { return nil }
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.httpMethod = method
        request.httpBody = body
        if body != nil {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let sem = DispatchSemaphore(value: 0)
        var output: (Int, String)?
        let job = URLSession.shared.dataTask(with: request) { data, response, _ in
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            let text = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
            if code > 0 { output = (code, text) }
            sem.signal()
        }
        lock.lock()
        task = job
        lock.unlock()
        job.resume()
        sem.wait()
        lock.lock()
        if task === job { task = nil }
        lock.unlock()
        return output
    }
}

private final class AppSession: SecretarySession {
    weak var model: MeetingModel?
    var sessionID: String?
    private let sendLock = NSLock()
    private let state = NSLock()
    private var process: Process?
    private var active: Process?
    private var stdin: FileHandle?
    private var stdout: FileHandle?
    private var pending = Data()
    private var chat: OllamaChat?

    func send(_ prompt: String) throws -> String {
        sendLock.lock()
        defer { sendLock.unlock() }
        guard let model else { throw SessionError.dead }
        switch model.backend {
        case .ollama:
            do {
                return try sendOllama(prompt, project: model.project)
            } catch SessionError.tooLong {
                throw SessionError.tooLong
            } catch {
                dropConversation()
                throw SessionError.dead
            }
        case .codex:
            do {
                return try sendCodex(codexText(prompt, project: model.project), project: model.project)
            } catch {
                dropConversation()
                throw SessionError.dead
            }
        case .claude:
            do {
                return try sendStream(prompt, argv: ClaudeLaunch.liveArgv(project: model.project), project: model.project)
            } catch {
                dropConversation()
                throw SessionError.dead
            }
        case .agy:
            do {
                return try sendStream(agyText(prompt, project: model.project), argv: AgyLaunch.liveArgv(), project: model.project)
            } catch {
                dropConversation()
                throw SessionError.dead
            }
        }
    }

    func close() {
        LocalHTTP.cancel()
        state.lock()
        let proc = active ?? process
        let input = stdin
        active = nil
        process = nil
        stdin = nil
        state.unlock()
        try? input?.close()
        proc?.terminate()
    }

    func reset() {
        state.lock()
        sessionID = nil
        chat = nil
        state.unlock()
        close()
        state.lock()
        pending.removeAll()
        stdout = nil
        state.unlock()
    }

    func requestNote(liveOnly: Bool) throws -> String {
        sendLock.lock()
        defer { sendLock.unlock() }
        do {
            return try noteBody(liveOnly: liveOnly)
        } catch {
            state.lock()
            let retry = sessionID != nil
            state.unlock()
            dropConversation()
            guard retry else { throw SessionError.dead }
            return try noteBody(liveOnly: liveOnly)
        }
    }

    private func noteBody(liveOnly: Bool) throws -> String {
        guard let model else { throw SessionError.dead }
        let prompt = cloudNotePrompt(model, liveOnly: liveOnly)
        switch model.backend {
        case .ollama:
            return try ollamaNote(model, liveOnly: liveOnly)
        case .claude:
            return try runOnce(
                argv: claudeNoteArgv(model),
                project: model.project,
                prompt: prompt,
                stream: true
            )
        case .agy:
            let argv = agyNoteArgv()
            return try runOnce(
                argv: argv,
                project: model.project,
                prompt: prompt,
                stream: argv.contains("stream-json")
            )
        case .codex:
            let git = gitRepo(model.project)
            let argv: [String]
            if let id = copySessionID() {
                argv = CodexLaunch.resumeArgv(id: id, project: model.project, gitRepo: git)
            } else {
                argv = CodexLaunch.execArgv(project: model.project, gitRepo: git)
            }
            return try runOnce(argv: argv, project: model.project, prompt: prompt, stream: false)
        }
    }

    private func codexText(_ prompt: String, project: String) -> String {
        if copySessionID() != nil { return prompt }
        return Prompts.live(project: project) + "\n\n" + prompt
    }

    private func agyText(_ prompt: String, project: String) -> String {
        state.lock()
        let alive = process?.isRunning == true
        state.unlock()
        if alive { return prompt }
        return Prompts.live(project: project) + "\n\n" + prompt
    }

    private func dropConversation() {
        state.lock()
        sessionID = nil
        chat = nil
        state.unlock()
        close()
    }

    private func sendOllama(_ prompt: String, project: String) throws -> String {
        if chat == nil {
            chat = OllamaChat(system: Prompts.live(project: project) + "\n" + contextPack(project: project).text)
        }
        guard var current = chat else { throw SessionError.dead }
        current.messages.append(OllamaMessage(role: "user", content: prompt))
        let reply: String
        do {
            reply = try postChat(try fittedBody(current))
        } catch SessionError.tooLong {
            throw SessionError.tooLong
        } catch {
            throw SessionError.dead
        }
        current.messages.append(OllamaMessage(role: "assistant", content: reply))
        chat = current
        return reply
    }

    private func sendCodex(_ prompt: String, project: String) throws -> String {
        let git = gitRepo(project)
        let argv: [String]
        if let id = copySessionID() {
            argv = CodexLaunch.resumeArgv(id: id, project: project, gitRepo: git)
        } else {
            argv = CodexLaunch.execArgv(project: project, gitRepo: git)
        }
        return try runOnce(argv: argv, project: project, prompt: prompt, stream: false)
    }

    private func sendStream(_ prompt: String, argv: [String], project: String) throws -> String {
        try ensureStream(argv: argv, project: project)
        state.lock()
        let input = stdin
        let output = stdout
        state.unlock()
        guard let input, let output, let line = Self.streamLine(prompt) else { throw SessionError.dead }
        do {
            try input.write(contentsOf: line)
        } catch {
            close()
            throw SessionError.dead
        }
        return try readReply(from: output, stream: true, overwriteID: true, pending: &pending)
    }

    private func ensureStream(argv: [String], project: String) throws {
        state.lock()
        let running = process?.isRunning == true
        state.unlock()
        if running { return }
        close()
        let started = try Self.launch(argv: argv, project: project)
        state.lock()
        process = started.process
        stdin = started.stdin
        stdout = started.stdout
        active = started.process
        pending.removeAll()
        state.unlock()
    }

    private func runOnce(argv: [String], project: String, prompt: String, stream: Bool) throws -> String {
        let started = try Self.launch(argv: argv, project: project)
        state.lock()
        active = started.process
        state.unlock()
        defer {
            state.lock()
            if active === started.process { active = nil }
            state.unlock()
            if started.process.isRunning {
                started.process.terminate()
            }
            started.process.waitUntilExit()
        }
        let payload: Data
        if stream {
            guard let line = Self.streamLine(prompt) else { throw SessionError.dead }
            payload = line
        } else {
            guard var data = prompt.data(using: .utf8) else { throw SessionError.dead }
            data.append(0x0A)
            payload = data
        }
        do {
            try started.stdin.write(contentsOf: payload)
            try started.stdin.close()
        } catch {
            throw SessionError.dead
        }
        var local = Data()
        return try readReply(from: started.stdout, stream: stream, overwriteID: false, pending: &local)
    }

    private func readReply(from stdout: FileHandle, stream: Bool, overwriteID: Bool, pending: inout Data) throws -> String {
        if !stream {
            let rest = stdout.readDataToEndOfFile()
            pending.append(rest)
            let text = String(data: pending, encoding: .utf8) ?? ""
            pending.removeAll()
            for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
                captureID(from: String(line), overwrite: overwriteID)
            }
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { throw SessionError.dead }
            return trimmed
        }
        var assistant = ""
        while let line = try nextLine(from: stdout, pending: &pending) {
            captureID(from: line, overwrite: overwriteID)
            guard let object = Self.jsonObject(line) else { continue }
            let type = object["type"] as? String ?? ""
            let text = Self.eventText(object) ?? ""
            if type == "assistant", !text.isEmpty {
                assistant = text
            }
            if type == "result" {
                if !text.isEmpty { return text }
                if !assistant.isEmpty { return assistant }
                throw SessionError.dead
            }
        }
        if !assistant.isEmpty { return assistant }
        throw SessionError.dead
    }

    private func nextLine(from handle: FileHandle, pending: inout Data) throws -> String? {
        while true {
            if let newline = pending.firstIndex(of: 0x0A) {
                let lineData = pending.subdata(in: 0..<newline)
                pending.removeSubrange(0...newline)
                return String(data: lineData, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
            do {
                guard let chunk = try handle.read(upToCount: 8192), !chunk.isEmpty else {
                    if pending.isEmpty { return nil }
                    let text = String(data: pending, encoding: .utf8)
                    pending.removeAll()
                    return text?.trimmingCharacters(in: .whitespacesAndNewlines)
                }
                pending.append(chunk)
            } catch {
                throw SessionError.dead
            }
        }
    }

    private func captureID(from line: String, overwrite: Bool) {
        let lowered = line.lowercased()
        guard lowered.contains("session") || line.contains("\"conversation\"") else { return }
        guard let id = SessionID.parse(from: line), !id.isEmpty else { return }
        state.lock()
        if sessionID == nil || overwrite { sessionID = id }
        state.unlock()
    }

    private func ollamaNote(_ model: MeetingModel, liveOnly _: Bool) throws -> String {
        let pack = contextPack(project: model.project, includeLiveNotes: false)
        let meeting = URL(fileURLWithPath: model.meetingDir)
        let finalText = model.meetingDir.isEmpty ? "" : fileText(meeting.appendingPathComponent("transcript-final.md"))
        let liveText = fileText(URL(fileURLWithPath: model.resolvedTranscriptPath))
        let notes = model.meetingDir.isEmpty ? "" : fileText(meeting.appendingPathComponent("live-notes.md"))
        let system = "Return only the markdown."
        let note = NotePrompt.ollama(
            pack: pack.text,
            packFiles: pack.files,
            template: Prompts.noteTemplate,
            transcript: finalText,
            liveTranscript: liveText,
            liveNotes: notes,
            budget: max(0, OllamaChat.budget - system.count)
        )
        var noteChat = OllamaChat(system: system)
        noteChat.messages.append(OllamaMessage(role: "user", content: note.prompt))
        return try postChat(try fittedBody(noteChat))
    }

    private func fittedBody(_ chat: OllamaChat) throws -> Data {
        guard chat.fitting().contains(where: { $0.role == "user" }) else {
            throw SessionError.tooLong
        }
        return OllamaLaunch.body(chat: chat)
    }

    private func fileText(_ url: URL) -> String {
        guard !url.path.isEmpty, url.path != "/" else { return "" }
        return (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }

    private func postChat(_ body: Data) throws -> String {
        guard let url = URL(string: "http://127.0.0.1:11434/api/chat"),
              let (code, text) = LocalHTTP.data(url: url, method: "POST", body: body, timeout: 120),
              code == 200,
              let data = text.data(using: .utf8),
              let raw = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let message = raw["message"] as? [String: Any],
              let content = message["content"] as? String,
              !content.isEmpty else { throw SessionError.dead }
        return content
    }

    private func contextPack(project: String, includeLiveNotes: Bool = true) -> ContextPackResult {
        guard let model, !project.isEmpty else {
            return ContextPack.build(files: [])
        }
        let terms = model.topicTerms.split(separator: "\n", omittingEmptySubsequences: false).compactMap { raw -> String? in
            let line = String(raw).trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.first == "#" { return nil }
            return line
        }
        let meetingVocab = model.meetingDir.isEmpty
            ? nil
            : URL(fileURLWithPath: model.meetingDir).appendingPathComponent("vocab-extra.txt")
        let skillVocab = RecorderPaths.skillVocab(script: model.recorderScript)
        let urls = ContextFiles.paths(
            root: URL(fileURLWithPath: project),
            topicTerms: terms,
            meetingVocab: meetingVocab,
            skillVocab: skillVocab
        )
        var packed: [PackedFile] = []
        for url in urls {
            guard let raw = try? String(contentsOf: url, encoding: .utf8) else { continue }
            guard let text = packText(url: url, raw: raw) else { continue }
            packed.append(PackedFile(path: url.path, text: text))
        }
        if includeLiveNotes, !model.meetingDir.isEmpty {
            let notes = URL(fileURLWithPath: model.meetingDir).appendingPathComponent("live-notes.md")
            if let text = try? String(contentsOf: notes, encoding: .utf8) {
                packed.append(PackedFile(path: notes.path, text: text))
            }
        }
        return ContextPack.build(files: packed)
    }

    private static let vocabNames: Set<String> = ["vocab.txt", "meeting-vocab.txt", "vocab-extra.txt"]

    private func packText(url: URL, raw: String) -> String? {
        guard Self.vocabNames.contains(url.lastPathComponent) else { return raw }
        let kept = raw.split(separator: "\n", omittingEmptySubsequences: false).compactMap { rawLine -> String? in
            let trimmed = String(rawLine).trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.first == "#" { return nil }
            return trimmed
        }
        if kept.isEmpty { return nil }
        return kept.joined(separator: "\n")
    }

    private func cloudNotePrompt(_ model: MeetingModel, liveOnly: Bool) -> String {
        let dir = model.meetingDir
        var lines = [
            Prompts.noteTemplate,
            "Write the meeting note. Return only the markdown.",
            "Read both transcripts. Where they disagree on a number, name, date, id, or issue number, the figure is (?) and both wordings are quoted.",
            dir + "/transcript-live.md",
            dir + "/transcript-final.md",
            dir + "/live-notes.md"
        ]
        if liveOnly {
            lines.append("transcript-final.md is missing. Use the live transcript.")
        }
        return lines.joined(separator: "\n")
    }

    private func copySessionID() -> String? {
        state.lock()
        defer { state.unlock() }
        guard let sessionID, !sessionID.isEmpty else { return nil }
        return sessionID
    }

    private func claudeNoteArgv(_ model: MeetingModel) -> [String] {
        if let id = copySessionID() {
            return ClaudeLaunch.noteArgv(project: model.project, sessionID: id)
        }
        return [
            "claude", "-p",
            "--input-format", "stream-json",
            "--output-format", "stream-json",
            "--permission-mode", "dontAsk",
            "--allowedTools", "Read,Grep,Glob,Bash(gh *)",
            "--disallowedTools", "Edit,Write",
            "--system-prompt", Prompts.noteTemplate
        ]
    }

    private func agyNoteArgv() -> [String] {
        if let id = copySessionID() {
            return AgyLaunch.noteArgv(sessionID: id)
        }
        return AgyLaunch.liveArgv()
    }

    private func gitRepo(_ project: String) -> Bool {
        let git = URL(fileURLWithPath: project).appendingPathComponent(".git").path
        return FileManager.default.fileExists(atPath: git)
    }

    private static func launch(argv: [String], project: String) throws -> (process: Process, stdin: FileHandle, stdout: FileHandle) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = argv
        if !project.isEmpty {
            process.currentDirectoryURL = URL(fileURLWithPath: project)
        }
        let input = Pipe()
        let output = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            throw SessionError.dead
        }
        return (process, input.fileHandleForWriting, output.fileHandleForReading)
    }

    private static func streamLine(_ prompt: String) -> Data? {
        let payload: [String: Any] = [
            "type": "user",
            "message": [
                "role": "user",
                "content": [
                    ["type": "text", "text": prompt]
                ]
            ]
        ]
        guard var data = try? JSONSerialization.data(withJSONObject: payload) else { return nil }
        data.append(0x0A)
        return data
    }

    private static func jsonObject(_ line: String) -> [String: Any]? {
        guard let data = line.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    private static func eventText(_ object: [String: Any]) -> String? {
        if let result = object["result"] as? String, !result.isEmpty { return result }
        guard let message = object["message"] as? [String: Any] else { return nil }
        if let content = message["content"] as? String, !content.isEmpty { return content }
        guard let parts = message["content"] as? [[String: Any]] else { return nil }
        let text = parts.compactMap { part -> String? in
            let kind = part["type"] as? String
            if kind == nil || kind == "text" { return part["text"] as? String }
            return nil
        }.joined()
        return text.isEmpty ? nil : text
    }
}
