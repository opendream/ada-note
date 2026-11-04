import Foundation

public struct RecorderStatus: Equatable {
    public var recording: Bool
    public var name: String?
    public var pid: Int?
}

public struct StartInfo: Equatable {
    public var transcript: String
    public var log: String
    public var pid: Int
    public var dir: String?
}

public struct StopInfo: Equatable {
    public var stopped: Bool
    public var pid: Int?
    public var name: String
    public var dir: String

    public init(stopped: Bool, pid: Int?, name: String, dir: String) {
        self.stopped = stopped
        self.pid = pid
        self.name = name
        self.dir = dir
    }
}

public enum RecorderClient {
    public static func parseStatus(_ stdout: String) -> RecorderStatus {
        let first = stdout.split(separator: "\n").first.map(String.init) ?? ""
        if first == "no active meeting" {
            return RecorderStatus(recording: false, name: nil, pid: nil)
        }
        let parts = first.split(separator: " ").map(String.init)
        let name = parts.first
        func field(_ key: String) -> String? {
            parts.first { $0.hasPrefix(key) }?.dropFirst(key.count).description
        }
        return RecorderStatus(
            recording: field("alive=") == "true",
            name: name,
            pid: Int(field("pid=") ?? "")
        )
    }

    public static func parseStart(_ stdout: String) -> StartInfo? {
        guard let obj = json(stdout),
              let transcript = obj["transcript"] as? String,
              let log = obj["log"] as? String,
              let pid = obj["pid"] as? Int else { return nil }
        return StartInfo(transcript: transcript, log: log, pid: pid, dir: obj["dir"] as? String)
    }

    public static func parseStop(_ stdout: String) -> StopInfo? {
        guard let obj = json(stdout),
              let stopped = obj["stopped"] as? Bool,
              let name = obj["name"] as? String,
              let dir = obj["dir"] as? String else { return nil }
        return StopInfo(stopped: stopped, pid: obj["pid"] as? Int, name: name, dir: dir)
    }

    private static func json(_ stdout: String) -> [String: Any]? {
        guard let data = stdout.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }
}

public enum StopAction: Equatable {
    case final
    case retry
    case askKill(pid: Int)
    case kill(pid: Int)
}

public enum StopGate {
    public static func decide(first: StopInfo, second: StopInfo?, confirmedKill: Bool) -> StopAction {
        if first.stopped { return .final }
        guard let second else { return .retry }
        if second.stopped { return .final }
        let pid = second.pid ?? first.pid ?? 0
        return confirmedKill ? .kill(pid: pid) : .askKill(pid: pid)
    }
}
