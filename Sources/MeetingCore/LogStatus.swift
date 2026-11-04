import Foundation

public enum RecorderProblem: Equatable {
    case microphonePermission
    case captureStalled
    case audioResumed
    case systemAudioPermission
    case tapAppMissing
    case sliceMissed
}

public enum LogStatus {
    public static func classify(_ line: String) -> RecorderProblem? {
        if line.contains("ERROR recorder exited by itself") { return .microphonePermission }
        if line.contains("capture stalled") { return .captureStalled }
        if line.contains("audio resumed") { return .audioResumed }
        if line.contains("process tap failed") || line.contains("System Audio Recording") { return .systemAudioPermission }
        if line.contains("WARNING: no running app named") { return .tapAppMissing }
        if line.contains("ERROR vad") || line.contains("ERROR window") || line.contains("ERROR chunk") { return .sliceMissed }
        return nil
    }

    public static func message(for problem: RecorderProblem) -> String {
        switch problem {
        case .microphonePermission:
            return "Microphone permission. Recording has stopped, and audio from here on is not kept."
        case .captureStalled:
            return "Capture stalled."
        case .audioResumed:
            return "Audio resumed."
        case .systemAudioPermission:
            return "System Audio Recording permission is missing for the app or meeting-capture."
        case .tapAppMissing:
            return "That call app is not running. Mic only, and the helper keeps rescanning."
        case .sliceMissed:
            return "That slice was not transcribed. Recording continues."
        }
    }
}
