import Foundation

public enum Backend: String, CaseIterable, Equatable {
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

    public init(onPath: Bool, ollamaUp: Bool, hasModel: Bool, pingOK: Bool) {
        self.onPath = onPath
        self.ollamaUp = ollamaUp
        self.hasModel = hasModel
        self.pingOK = pingOK
    }

    public func ready(for backend: Backend) -> Bool {
        guard onPath else { return false }
        if backend == .ollama { return ollamaUp && hasModel }
        return pingOK
    }
}

public struct RecognizerCheck: Equatable {
    public var cli: Bool
    public var model: Bool
    public var vad: Bool
    public var ffmpeg: Bool
    public var swiftc: Bool

    public init(cli: Bool, model: Bool, vad: Bool, ffmpeg: Bool, swiftc: Bool) {
        self.cli = cli
        self.model = model
        self.vad = vad
        self.ffmpeg = ffmpeg
        self.swiftc = swiftc
    }

    public var ready: Bool { cli && model && vad && ffmpeg && swiftc }
}

public enum AttachBrief {
    public static func prompt(notes: String, recent: [TranscriptLine]) -> String {
        let speech = recent.filter { $0.kind == .speech }.suffix(20).map { line in
            "[" + line.stamp + "] " + line.text
        }
        if notes.isEmpty { return speech.joined(separator: "\n") }
        if speech.isEmpty { return notes }
        let head = notes.hasSuffix("\n") ? String(notes.dropLast()) : notes
        return ([head] + speech).joined(separator: "\n")
    }
}

public enum PrivacyNotice {
    public static func text(for backend: Backend) -> String {
        if backend == .ollama { return "Transcript text stays on this Mac." }
        return "Transcript text leaves the Mac."
    }
}

public enum PastMeetings {
    public static func newestUnnoted(root: URL) -> URL? {
        let fm = FileManager.default
        guard let children = try? fm.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: []
        ) else { return nil }

        var bestURL: URL?
        var bestDate = Date.distantPast
        for child in children {
            guard (try? child.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { continue }
            let meta = child.appendingPathComponent("meta.json")
            guard let metaValues = try? meta.resourceValues(forKeys: [.isRegularFileKey, .contentModificationDateKey]),
                  metaValues.isRegularFile == true else { continue }
            if containsSummaryNote(child) { continue }
            let date = metaValues.contentModificationDate ?? .distantPast
            if bestURL == nil || date > bestDate {
                bestDate = date
                bestURL = child
            }
        }
        return bestURL
    }

    private static func containsSummaryNote(_ folder: URL) -> Bool {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: folder.path) else { return true }
        for name in names where name.hasPrefix("summary") && name.hasSuffix(".md") {
            var isDir: ObjCBool = false
            let path = folder.appendingPathComponent(name).path
            if FileManager.default.fileExists(atPath: path, isDirectory: &isDir), !isDir.boolValue {
                return true
            }
        }
        return false
    }
}
