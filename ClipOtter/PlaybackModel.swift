import Foundation
import AVFoundation
import Observation

/// Wraps an AVPlayer and tracks the current play head so the transcript can
/// highlight the active segment and seek on click.
@MainActor
@Observable
final class PlaybackModel {
    let player = AVPlayer()
    var currentTime: TimeInterval = 0

    nonisolated(unsafe) private var timeObserver: Any?
    private var loadedURL: URL?

    init() {
        let interval = CMTime(seconds: 0.25, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            self?.currentTime = time.seconds
        }
    }

    func load(_ url: URL?) {
        guard loadedURL != url else { return }
        loadedURL = url
        currentTime = 0
        if let url {
            player.replaceCurrentItem(with: AVPlayerItem(url: url))
        } else {
            player.replaceCurrentItem(with: nil)
        }
    }

    func seek(to seconds: TimeInterval, play: Bool = true) {
        let target = CMTime(seconds: max(0, seconds), preferredTimescale: 600)
        player.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero)
        if play { player.play() }
    }

    deinit {
        if let timeObserver {
            player.removeTimeObserver(timeObserver)
        }
    }
}
