import Foundation

public enum Setup {
    public static func commands(root: URL, missingFfmpeg: Bool, missingSwiftc: Bool) -> [String] {
        let home = quoted(root.path)
        let model = quoted(root.appendingPathComponent("models/Qwen3-ASR-1.7B-Q8_0.gguf").path)
        let vad = quoted(root.appendingPathComponent("models/silero-vad-v6.2-F32.gguf").path)
        // Tool lines before git and cmake. Those fail when the tools are missing.
        var lines: [String] = []
        if missingSwiftc {
            lines.append("xcode-select --install")
        }
        if missingFfmpeg {
            lines.append("brew install ffmpeg")
        }
        lines.append("git clone https://github.com/handy-computer/transcribe.cpp \(home)")
        lines.append("cd \(home) && cmake -B build && cmake --build build -j")
        lines.append("curl -L -o \(model) https://huggingface.co/handy-computer/Qwen3-ASR-1.7B-gguf/resolve/main/Qwen3-ASR-1.7B-Q8_0.gguf")
        lines.append("curl -L -o \(vad) https://huggingface.co/handy-computer/silero-vad-v6.2-gguf/resolve/main/silero-vad-v6.2-F32.gguf")
        return lines
    }

    private static func quoted(_ path: String) -> String {
        "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
