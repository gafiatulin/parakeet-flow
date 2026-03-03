import AppKit

enum AudioFeedbackManager {
    static func playStartSound() {
        NSSound(named: "Tink")?.play()
    }

    static func playStopSound() {
        NSSound(named: "Pop")?.play()
    }
}

