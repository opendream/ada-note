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
