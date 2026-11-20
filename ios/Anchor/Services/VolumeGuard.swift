import AVFoundation
import MediaPlayer
import SwiftUI
import UIKit

/// Keeps the volume from going below 3 of 16 notches during a session (outside library mode). iOS has no API to
/// set the volume; the slider inside a system volume view does it, so one sits invisibly in Anchor's window.
@MainActor
final class VolumeGuard {
    private var observation: NSKeyValueObservation?
    private(set) var isEnforcing = false
    weak var slider: UISlider?

    func setEnforcing(_ on: Bool) {
        guard on != isEnforcing else { return }
        isEnforcing = on
        if on {
            observation = AVAudioSession.sharedInstance().observe(\.outputVolume, options: [.initial, .new]) { @Sendable [weak self] session, change in
                let volume = change.newValue ?? session.outputVolume
                Task { @MainActor in self?.check(volume) }
            }
        } else {
            observation?.invalidate()
            observation = nil
        }
    }

    private func check(_ volume: Float) {
        guard isEnforcing, let target = VolumeRule.corrected(volume), let slider else { return }
        // Setting it in the same turn as the button press is ignored; a moment later it sticks.
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(50))
            slider.setValue(target, animated: false)
            slider.sendActions(for: .valueChanged)
        }
    }
}

/// The invisible system volume view whose slider `VolumeGuard` moves.
struct VolumeHost: UIViewRepresentable {
    let guardian: VolumeGuard

    func makeUIView(context: Context) -> MPVolumeView {
        let view = MPVolumeView(frame: CGRect(x: -200, y: -200, width: 100, height: 40))
        view.alpha = 0.01
        view.isUserInteractionEnabled = false
        guardian.slider = view.subviews.compactMap { $0 as? UISlider }.first
        return view
    }

    func updateUIView(_ view: MPVolumeView, context: Context) {
        if guardian.slider == nil {
            guardian.slider = view.subviews.compactMap { $0 as? UISlider }.first
        }
    }
}
