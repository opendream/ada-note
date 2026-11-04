import Foundation

public struct StartCommand: Equatable {
    public var python: String
    public var script: String
    public var workingDirectory: String
    public var name: String
    public var device: String
    public var lang: String
    public var tapApp: String?
    public var replayWav: String?

    public init(python: String, script: String, workingDirectory: String, name: String, device: String, lang: String, tapApp: String?, replayWav: String?) {
        self.python = python
        self.script = script
        self.workingDirectory = workingDirectory
        self.name = name
        self.device = device
        self.lang = lang
        self.tapApp = tapApp
        self.replayWav = replayWav
    }

    public func argv() -> [String] {
        var args = [python, script, "start", name, "--device", device, "--lang", lang]
        if let tapApp, !tapApp.isEmpty {
            args.append("--tap-app")
            args.append(tapApp)
        }
        if let replayWav, !replayWav.isEmpty {
            args.append("--replay")
            args.append(replayWav)
        }
        return args
    }
}
