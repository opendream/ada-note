import Foundation

public enum MeetingRoot {
    /// Directory that holds one folder per meeting.
    /// `$MEETING_HOME` when set, otherwise `<git toplevel>/.meetings`, otherwise `<picked>/.meetings`.
    /// `gitTopLevel` overrides the git lookup. Production passes nil, which runs git only when a `.git` entry exists above the folder.
    public static func meetingsDirectory(
        picked: String,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        gitTopLevel: ((String) -> String?)? = nil
    ) -> URL {
        if let home = environment["MEETING_HOME"]?.trimmingCharacters(in: .whitespacesAndNewlines), !home.isEmpty {
            return expandedHome(home, picked: picked)
        }
        let top = gitTopLevel?(picked) ?? (gitTopLevel == nil ? GitTop.level(of: picked) : nil)
        let base = (top?.isEmpty == false) ? top! : picked
        return URL(fileURLWithPath: base, isDirectory: true)
            .appendingPathComponent(".meetings", isDirectory: true)
    }

    public static func meetingFolder(
        picked: String,
        name: String,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        gitTopLevel: ((String) -> String?)? = nil
    ) -> URL {
        meetingsDirectory(picked: picked, environment: environment, gitTopLevel: gitTopLevel)
            .appendingPathComponent(name, isDirectory: true)
    }

    private static func expandedHome(_ home: String, picked: String) -> URL {
        let expanded = (home as NSString).expandingTildeInPath
        if expanded.hasPrefix("/") {
            return URL(fileURLWithPath: expanded, isDirectory: true)
        }
        return URL(fileURLWithPath: picked, isDirectory: true)
            .appendingPathComponent(expanded, isDirectory: true)
    }
}

enum GitTop {
    static func level(of picked: String) -> String? {
        guard ancestorHasGit(picked) else { return nil }
        return revParse(picked)
    }

    private static func ancestorHasGit(_ picked: String) -> Bool {
        let fm = FileManager.default
        var url = URL(fileURLWithPath: picked, isDirectory: true)
        var last = ""
        while url.path != last {
            if fm.fileExists(atPath: url.appendingPathComponent(".git").path) { return true }
            last = url.path
            url.deleteLastPathComponent()
        }
        return false
    }

    private static func revParse(_ picked: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["-C", picked, "rev-parse", "--show-toplevel"]
        process.standardError = FileHandle.nullDevice
        let output = Pipe()
        process.standardOutput = output
        do {
            try process.run()
        } catch {
            return nil
        }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        let text = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return text.isEmpty ? nil : text
    }
}
