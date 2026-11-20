import AVFoundation
import os

/// Anchor's sound. During a session a silent track keeps Anchor running in the background (iOS would otherwise
/// pause it while the phone sits still and GPS has nothing new), so it can see every unlock. On the phone it adds
/// a voice that reads your phone time and an alarm that loops until you lock the phone or walk away. Everything
/// mixes with other audio and plays even on silent.
@MainActor
final class Escalator: NSObject, AVSpeechSynthesizerDelegate {
    private nonisolated static let log = Logger(subsystem: "com.sammg123.anchor", category: "escalator")

    private let session = AVAudioSession.sharedInstance()
    private let speech = AVSpeechSynthesizer()
    private var keepAlive: AVAudioPlayer?
    private var alarm: AVAudioPlayer?
    private var wantsKeepAlive = false
    private var wantsAlarm = false
    private var interruptionObserver: NSObjectProtocol?

    override init() {
        super.init()
        speech.delegate = self
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification, object: nil, queue: .main
        ) { [weak self] note in
            let ended = (note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt)
                .flatMap(AVAudioSession.InterruptionType.init(rawValue:)) == .ended
            MainActor.assumeIsolated { if ended { self?.resumeAfterInterruption() } }
        }
    }

    // MARK: - Session lifetime

    func startKeepAlive() {
        wantsKeepAlive = true
        guard keepAlive?.isPlaying != true else { return }
        keepAlive = loop("silence", volume: 1)
    }

    func stopEverything() {
        wantsKeepAlive = false
        keepAlive?.stop()
        keepAlive = nil
        stopEscalation()
        release()
    }

    // MARK: - On the phone

    func speak(_ line: String) {
        guard !wantsAlarm, activate() else { return }
        let utterance = AVSpeechUtterance(string: line)
        utterance.rate = 0.5
        utterance.volume = 1
        speech.speak(utterance)
    }

    func setAlarm(_ on: Bool) {
        guard on != wantsAlarm else { return }
        wantsAlarm = on
        if on {
            speech.stopSpeaking(at: .immediate)
            alarm = loop("alarm", volume: 1)
        } else {
            alarm?.stop()
            alarm = nil
            release()
        }
    }

    /// Voice and alarm off; the keep-alive track keeps playing.
    func stopEscalation() {
        guard wantsAlarm || alarm != nil || speech.isSpeaking else { return }
        wantsAlarm = false
        alarm?.stop()
        alarm = nil
        speech.stopSpeaking(at: .immediate)
        release()
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor [weak self] in self?.release() }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor [weak self] in self?.release() }
    }

    // MARK: - Audio session

    private func loop(_ name: String, volume: Float) -> AVAudioPlayer? {
        guard activate(), let url = Bundle.main.url(forResource: name, withExtension: "wav") else {
            Self.log.error("\(name, privacy: .public) could not start")
            return nil
        }
        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.numberOfLoops = -1
            player.volume = volume
            guard player.play() else {
                Self.log.error("\(name, privacy: .public) refused to play")
                return nil
            }
            return player
        } catch {
            Self.log.error("\(name, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    /// A call, Siri or a timer stops our audio; bring back whatever is still wanted.
    private func resumeAfterInterruption() {
        if wantsKeepAlive {
            keepAlive = nil
            startKeepAlive()
        }
        if wantsAlarm {
            alarm = loop("alarm", volume: 1)
        }
    }

    private func activate() -> Bool {
        do {
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)
            return true
        } catch {
            Self.log.error("audio session failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    /// Let the session go once nothing of ours needs it.
    private func release() {
        guard !wantsKeepAlive, !wantsAlarm, alarm == nil, !speech.isSpeaking else { return }
        do {
            try session.setActive(false, options: [.notifyOthersOnDeactivation])
        } catch {
            Self.log.error("audio session release failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
