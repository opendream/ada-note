import Foundation

public protocol SecretarySession: AnyObject {
    var sessionID: String? { get }
    func send(_ prompt: String) throws -> String
    func close()
    func reset()
}

public enum SessionError: Error, Equatable {
    case dead
    case tooLong

    public static let tooLongStatus = "The turn was too long."
}

public final class FakeSession: SecretarySession {
    public var sessionID: String? = "fake"
    public var prompts: [String] = []
    public var reply: String
    public var fail = false
    public init(reply: String) { self.reply = reply }
    public func send(_ prompt: String) throws -> String {
        prompts.append(prompt)
        if fail { throw SessionError.dead }
        return reply
    }
    public func close() {}
    public func reset() {}
}

public enum TurnWatch: Equatable {
    case running
    case waiting
    case done

    public static func watch(started: Date, now: Date, finished: Bool) -> TurnWatch {
        if finished { return .done }
        if now.timeIntervalSince(started) >= 30 { return .waiting }
        return .running
    }
}

struct TurnClaim {
    var ownsPump: Bool
    var reconnect: Bool
}

public final class MeetingLoop {
    public var notes = ""
    public var status = ""
    public var tailStopped = false
    private var queue = TurnQueue()
    private let session: SecretarySession
    private let lock = NSLock()
    private var pumping = false
    private var needsReconnect = false
    private var stopSending = false

    public init(session: SecretarySession) { self.session = session }

    public func onSpeech(_ line: TranscriptLine) {
        let claim = claimSpeech(line)
        if claim.ownsPump { drain() }
    }

    public func onQuestion(_ text: String) {
        let claim = claimQuestion(text)
        if claim.ownsPump { drain() }
    }

    func claimSpeech(_ line: TranscriptLine) -> TurnClaim {
        claim { queue.pushSpeech(line) }
    }

    func claimQuestion(_ text: String) -> TurnClaim {
        claim { queue.pushQuestion(text) }
    }

    func sendLead(_ prompt: String) throws {
        lock.lock()
        let blocked = stopSending
        lock.unlock()
        if blocked { return }
        do {
            _ = try session.send(prompt)
            lock.lock()
            if status == "backend dead" || status == SessionError.tooLongStatus { status = "" }
            lock.unlock()
        } catch {
            lock.lock()
            noteFailure(error)
            pumping = false
            lock.unlock()
            throw error
        }
    }

    func discardQueued() {
        lock.lock()
        queue = TurnQueue()
        needsReconnect = false
        stopSending = true
        pumping = false
        lock.unlock()
    }

    func drain() {
        while true {
            lock.lock()
            if stopSending {
                queue = TurnQueue()
                pumping = false
                lock.unlock()
                return
            }
            guard let turn = queue.takeNext() else {
                pumping = false
                lock.unlock()
                return
            }
            if stopSending {
                queue = TurnQueue()
                pumping = false
                lock.unlock()
                return
            }
            let prompt: String
            let stamp: String
            switch turn {
            case .question(let text):
                prompt = text
                stamp = ""
            case .speech(let batch):
                prompt = batch.lines.map { "[" + $0.stamp + "] " + $0.text }.joined(separator: "\n")
                stamp = batch.lines.last?.stamp ?? ""
            }
            lock.unlock()
            do {
                let reply = try session.send(prompt)
                let entries = LiveNotes.entries(from: reply, stamp: stamp)
                lock.lock()
                if !entries.isEmpty {
                    notes += entries.joined(separator: "\n") + "\n"
                }
                if status == "backend dead" || status == SessionError.tooLongStatus { status = "" }
                queue.finish()
                lock.unlock()
            } catch {
                lock.lock()
                noteFailure(error)
                queue.finish()
                pumping = false
                lock.unlock()
                return
            }
        }
    }

    func prepareForNewMeeting() {
        lock.lock()
        notes = ""
        status = ""
        needsReconnect = false
        queue = TurnQueue()
        pumping = false
        stopSending = false
        lock.unlock()
    }

    func markDead() {
        lock.lock()
        status = "backend dead"
        needsReconnect = true
        lock.unlock()
    }

    func copyNotes() -> String {
        lock.lock()
        defer { lock.unlock() }
        return notes
    }

    private func noteFailure(_ error: Error) {
        if case SessionError.tooLong = error {
            status = SessionError.tooLongStatus
            needsReconnect = false
        } else {
            status = "backend dead"
            needsReconnect = true
        }
    }

    private func claim(_ push: () -> Void) -> TurnClaim {
        lock.lock()
        defer { lock.unlock() }
        push()
        if pumping { return TurnClaim(ownsPump: false, reconnect: false) }
        pumping = true
        let reconnect = needsReconnect
        needsReconnect = false
        return TurnClaim(ownsPump: true, reconnect: reconnect)
    }
}
