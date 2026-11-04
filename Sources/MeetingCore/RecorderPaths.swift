import Foundation

public enum RecorderPaths {
    public static let environmentKey = "ADA_NOTE_RECORDER"

    /// `meeting.py` from the meeting-secretary skill.
    /// An `ADA_NOTE_RECORDER` value wins. Otherwise an installed Claude marketplace
    /// copy wins over a `noomz-claude-skills` checkout sitting next to this app.
    /// When neither file exists, the marketplace path is still returned so the
    /// window can show a concrete place to install the skill.
    public static func script(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        home: String = NSHomeDirectory(),
        executable: URL = URL(fileURLWithPath: CommandLine.arguments.first ?? "MeetingWindow"),
        fileExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }
    ) -> String {
        if let raw = environment[environmentKey] {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
        }
        let installed = marketplaceScript(home: home)
        if fileExists(installed) { return installed }
        if let sibling = siblingScript(executable: executable, fileExists: fileExists) {
            return sibling
        }
        return installed
    }

    public static func marketplaceScript(home: String) -> String {
        URL(fileURLWithPath: home, isDirectory: true)
            .appendingPathComponent(".claude", isDirectory: true)
            .appendingPathComponent("plugins", isDirectory: true)
            .appendingPathComponent("marketplaces", isDirectory: true)
            .appendingPathComponent("noomz-claude-skills", isDirectory: true)
            .appendingPathComponent("skills", isDirectory: true)
            .appendingPathComponent("meeting-secretary", isDirectory: true)
            .appendingPathComponent("scripts", isDirectory: true)
            .appendingPathComponent("meeting.py")
            .path
    }

    public static func siblingScript(executable: URL, fileExists: (String) -> Bool) -> String? {
        var dir = executable.deletingLastPathComponent()
        for _ in 0..<8 {
            let parent = dir.deletingLastPathComponent()
            if parent.path == dir.path { return nil }
            let candidate = parent
                .appendingPathComponent("noomz-claude-skills", isDirectory: true)
                .appendingPathComponent("skills", isDirectory: true)
                .appendingPathComponent("meeting-secretary", isDirectory: true)
                .appendingPathComponent("scripts", isDirectory: true)
                .appendingPathComponent("meeting.py")
                .path
            if fileExists(candidate) { return candidate }
            dir = parent
        }
        return nil
    }

    public static func skillVocab(
        script: String,
        fileExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }
    ) -> URL? {
        let vocab = URL(fileURLWithPath: script)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("assets", isDirectory: true)
            .appendingPathComponent("vocab.txt")
        return fileExists(vocab.path) ? vocab : nil
    }
}
