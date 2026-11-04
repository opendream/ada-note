import Foundation

public enum ClaudeLaunch {
    public static func liveArgv(project: String) -> [String] {
        [
            "claude", "-p",
            "--input-format", "stream-json",
            "--output-format", "stream-json",
            "--permission-mode", "dontAsk",
            "--restricted",
            "--allowedTools", "Read,Grep,Glob",
            "--disallowedTools", "Bash,Edit,Write",
            "--system-prompt", Prompts.live(project: project)
        ]
    }

    public static func noteArgv(project _: String, sessionID: String) -> [String] {
        [
            "claude", "-p",
            "--resume", sessionID,
            "--input-format", "stream-json",
            "--output-format", "stream-json",
            "--permission-mode", "dontAsk",
            "--allowedTools", "Read,Grep,Glob,Bash(gh *)",
            "--disallowedTools", "Edit,Write",
            "--system-prompt", Prompts.noteTemplate
        ]
    }
}

public enum AgyLaunch {
    public static func liveArgv() -> [String] {
        ["agy", "--print", "--input-format", "stream-json", "--output-format", "stream-json", "--mode", "plan"]
    }

    public static func noteArgv(sessionID: String) -> [String] {
        ["agy", "--print", "--mode", "plan", "--conversation", sessionID]
    }
}

public enum CodexLaunch {
    public static func execArgv(project: String, gitRepo: Bool) -> [String] {
        var args = ["codex", "exec", "-C", project, "--sandbox", "read-only"]
        if !gitRepo { args.append("--skip-git-repo-check") }
        return args
    }

    public static func resumeArgv(id: String, project: String, gitRepo: Bool) -> [String] {
        var args = ["codex", "exec", "resume", id, "-C", project, "--sandbox", "read-only"]
        if !gitRepo { args.append("--skip-git-repo-check") }
        return args
    }
}

public enum OllamaLaunch {
    public static func body(chat: OllamaChat) -> Data {
        let messages = chat.fitting().map { ["role": $0.role, "content": $0.content] }
        let payload: [String: Any] = [
            "model": "qwen3.8",
            "messages": messages,
            "stream": false,
            "options": ["num_ctx": OllamaChat.numCtx]
        ]
        return (try? JSONSerialization.data(withJSONObject: payload)) ?? Data()
    }
}

public enum SessionID {
    public static func parse(from text: String) -> String? {
        if let data = text.data(using: .utf8),
           let raw = try? JSONSerialization.jsonObject(with: data),
           let object = raw as? [String: Any] {
            for key in ["session_id", "sessionId", "conversation"] {
                if let value = object[key] as? String { return value }
            }
        }
        return firstUUID(in: text)
    }

    private static func firstUUID(in text: String) -> String? {
        let pattern = "[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              let found = Range(match.range, in: text) else { return nil }
        return String(text[found])
    }
}
