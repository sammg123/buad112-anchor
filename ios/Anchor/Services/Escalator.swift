import AVFoundation
import os

/// The loud part: a voice that reads your phone time over whatever is playing, then an alarm that loops until
/// you lock the phone or walk away. Plays even on silent (the playback category ignores the switch) and from the
/// background, because Anchor stays running for location and declares background audio. Other audio is ducked,
/// never stopped, which is what iOS allows an app to start from the background.
@MainActor
final class Escalator: NSObject, AVSpeechSynthesizerDelegate {
    private nonisolated static let log = Logger(subsystem: "com.sammg123.anchor", category: "escalator")
    private static let releaseRetryDelay: Duration = .milliseconds(400)

    private let session = AVAudioSession.sharedInstance()
    private let speech = AVSpeechSynthesizer()
    private var alarm: AVAudioPlayer?
    /// The alarm is wanted (the model says so), whether or not it is playing right now.
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
            startAlarm()
        } else {
            alarm?.stop()
            alarm = nil
            release()
        }
    }

    func stopAll() {
        guard wantsAlarm || alarm != nil || speech.isSpeaking else { return }
        wantsAlarm = false
        alarm?.stop()
        alarm = nil
        speech.stopSpeaking(at: .immediate)
        release()
    }

    // MARK: - Speech finished

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor [weak self] in self?.release() }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor [weak self] in self?.release() }
    }

    // MARK: - Audio session

    private func startAlarm() {
        guard alarm?.isPlaying != true else { return }
        guard activate(), let url = Bundle.main.url(forResource: "alarm", withExtension: "wav") else {
            Self.log.error("alarm could not start")
            return
        }
        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.numberOfLoops = -1
            player.volume = 1
            guard player.play() else {
                Self.log.error("alarm refused to play")
                return
            }
            alarm = player
        } catch {
            Self.log.error("alarm failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// A call, Siri or a timer stops the alarm; bring it back if it is still wanted.
    private func resumeAfterInterruption() {
        guard wantsAlarm else { return }
        alarm = nil
        startAlarm()
    }

    private func activate() -> Bool {
        do {
            try session.setCategory(.playback, mode: .voicePrompt, options: [.duckOthers])
            try session.setActive(true)
            return true
        } catch {
            Self.log.error("audio session failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    /// Give other apps their volume back once nothing of ours is playing. iOS can report the session busy right
    /// after audio stops, so try once more shortly after.
    private func release(retrying: Bool = true) {
        guard !wantsAlarm, alarm == nil, !speech.isSpeaking else { return }
        do {
            try session.setActive(false, options: [.notifyOthersOnDeactivation])
        } catch {
            guard retrying else {
                Self.log.error("audio session release failed: \(error.localizedDescription, privacy: .public)")
                return
            }
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: Self.releaseRetryDelay)
                self?.release(retrying: false)
            }
        }
    }
}
