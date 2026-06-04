import SwiftUI
import AVKit

/// AppKit `AVPlayerView` wrapped for SwiftUI.
///
/// We deliberately avoid SwiftUI's `VideoPlayer`: on macOS 26 it aborts while
/// resolving its internal `VideoPlayerView`'s superclass metadata
/// ("failed to demangle superclass ... 'So12AVPlayerViewC'"). Using
/// `AVPlayerView` directly sidesteps that and gives native macOS controls.
struct PlayerView: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.player = player
        view.controlsStyle = .inline
        view.videoGravity = .resizeAspect
        view.showsFullScreenToggleButton = true
        return view
    }

    func updateNSView(_ nsView: AVPlayerView, context: Context) {
        if nsView.player !== player {
            nsView.player = player
        }
    }
}
