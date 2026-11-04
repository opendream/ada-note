import Foundation

public struct OllamaNote: Equatable {
    public var prompt: String
    public var shortened: Bool
}

public enum NotePrompt {
    public static let budget = 7000

    public static func ollama(
        pack: String,
        packFiles: [String],
        template: String,
        transcript: String,
        liveTranscript: String = "",
        liveNotes: String = "",
        budget: Int = NotePrompt.budget
    ) -> OllamaNote {
        let speech = speechLines(transcript)
        var body = "Pack files: " + packFiles.joined(separator: ", ") + "\n" + pack + "\n" + template + "\n"
        var shortened = false
        let marker = "Transcript was shortened.\n"
        if liveTranscript.isEmpty && liveNotes.isEmpty {
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
        func fits(_ addition: String) -> Bool {
            body.count + addition.count + marker.count <= budget
        }
        if !liveNotes.isEmpty {
            let block = "Live notes:\n" + liveNotes.trimmingCharacters(in: .whitespacesAndNewlines) + "\n"
            if fits(block) {
                body += block
            } else {
                let room = budget - marker.count - body.count
                if room > 0 { body += String(block.prefix(room)) }
                shortened = true
            }
        }
        func appendSpeech(_ label: String, _ lines: [String]) {
            guard !shortened, !lines.isEmpty else { return }
            if !fits(label) {
                shortened = true
                return
            }
            body += label
            for line in lines {
                let addition = line + "\n"
                if !fits(addition) {
                    shortened = true
                    return
                }
                body += addition
            }
        }
        appendSpeech("Final transcript:\n", speech)
        appendSpeech("Live transcript:\n", speechLines(liveTranscript))
        if shortened { body += marker }
        return OllamaNote(prompt: body, shortened: shortened)
    }

    private static func speechLines(_ transcript: String) -> [String] {
        transcript.split(separator: "\n").compactMap { raw -> String? in
            guard let line = TranscriptLine.parse(String(raw)), line.kind == .speech else { return nil }
            return "[" + line.stamp + "] " + line.text
        }
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

    /// Keeps the system message and the newest user message. Older turns drop first.
    /// Empty when the newest user message cannot fit beside the system message.
    public func fitting() -> [OllamaMessage] {
        guard let system = messages.first else { return [] }
        let rest = Array(messages.dropFirst())
        if rest.isEmpty { return [system] }
        var turns: [[OllamaMessage]] = []
        for message in rest {
            if message.role == "user" || turns.isEmpty {
                turns.append([message])
            } else {
                turns[turns.count - 1].append(message)
            }
        }
        guard let newest = turns.last else { return [system] }
        let newestUserCount = newest.first(where: { $0.role == "user" })?.content.count ?? newest[0].content.count
        if system.content.count + newestUserCount > Self.budget { return [] }
        var count = system.content.count
        var keptNewest: [OllamaMessage] = []
        var keptUser = false
        for message in newest {
            if message.role == "user" && !keptUser {
                keptNewest.append(message)
                count += message.content.count
                keptUser = true
                continue
            }
            if count + message.content.count > Self.budget { break }
            keptNewest.append(message)
            count += message.content.count
        }
        var older: [OllamaMessage] = []
        if turns.count > 1 {
            for turn in turns.dropLast().reversed() {
                let turnCount = turn.reduce(0) { $0 + $1.content.count }
                if count + turnCount > Self.budget { break }
                older.insert(contentsOf: turn, at: 0)
                count += turnCount
            }
        }
        return [system] + older + keptNewest
    }
}
