import Foundation

public struct PackedFile: Equatable {
    public var path: String
    public var text: String
    public init(path: String, text: String) {
        self.path = path
        self.text = text
    }
}

public struct ContextPackResult: Equatable {
    public var text: String
    public var files: [String]
    public var cut: Bool
}

public enum ContextPack {
    public static let cap = 3000

    public static func build(files: [PackedFile]) -> ContextPackResult {
        var out = ""
        var used: [String] = []
        var cut = false
        let notice = "\n\nPack was cut at 3000 characters."
        for file in files {
            let block = "\n\n# " + file.path + "\n" + file.text
            if out.count + block.count > cap {
                cut = true
                break
            }
            out += block
            used.append(file.path)
        }
        if cut { out += notice }
        return ContextPackResult(text: out, files: used, cut: cut)
    }
}

public enum ContextFiles {
    public static func paths(root: URL, topicTerms: [String], meetingVocab: URL?, skillVocab: URL?) -> [URL] {
        let fm = FileManager.default
        var urls: [URL] = []
        for name in ["CLAUDE.md", "AGENTS.md", "README", "README.md"] {
            let url = root.appendingPathComponent(name)
            if fm.fileExists(atPath: url.path) { urls.append(url) }
        }
        if !topicTerms.isEmpty {
            for dir in [".planning", "plans", "docs"] {
                let base = root.appendingPathComponent(dir)
                guard let items = try? fm.contentsOfDirectory(at: base, includingPropertiesForKeys: nil) else { continue }
                for url in items.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                    let name = url.lastPathComponent
                    if topicTerms.contains(where: { name.contains($0) }) { urls.append(url) }
                }
            }
        }
        for extra in [skillVocab, root.appendingPathComponent(".claude/meeting-vocab.txt"), meetingVocab] {
            if let extra, fm.fileExists(atPath: extra.path) { urls.append(extra) }
        }
        return urls
    }
}
