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
