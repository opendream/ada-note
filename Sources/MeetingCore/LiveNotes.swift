import Foundation

public enum LiveNotes {
    public static let markers = ["❓", "⚠️", "✅", "📌", "📎", "🔎"]

    public static func entries(from reply: String, stamp: String) -> [String] {
        reply.split(separator: "\n", omittingEmptySubsequences: false).compactMap { raw in
            let line = String(raw).trimmingCharacters(in: .whitespaces)
            guard markers.contains(where: { line.hasPrefix($0) }) else { return nil }
            return "- [" + stamp + "] " + line
        }
    }
}
