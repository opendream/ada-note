import Foundation

public enum SummaryNames {
    public static func next(existing: [String]) -> String {
        if !existing.contains("summary.md") { return "summary.md" }
        var n = 2
        while existing.contains("summary-v" + String(n) + ".md") { n += 1 }
        return "summary-v" + String(n) + ".md"
    }
}
