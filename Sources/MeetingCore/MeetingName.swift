import Foundation

public enum MeetingName {
    public static func isValid(_ name: String) -> Bool {
        guard !name.isEmpty else { return false }
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_.")
        return name.unicodeScalars.allSatisfy { allowed.contains($0) }
    }

    public static func defaultName(date: Date, slug: String, timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        let clean = slug.isEmpty ? "meeting" : slug
        return formatter.string(from: date) + "-" + clean
    }
}
