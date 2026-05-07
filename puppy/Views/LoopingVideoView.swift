import SwiftUI
import AVFoundation
import AppKit

struct LoopingVideoView: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> NSView {
        LoopingVideoNSView(url: url)
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

/// AVPlayerLayer를 backing layer로 직접 사용 → HEVC/ProRes alpha 채널 자동 합성.
/// AVPlayerView는 alpha 무시하므로 사용 금지.
final class LoopingVideoNSView: NSView {
    private let queuePlayer: AVQueuePlayer
    private var looper: AVPlayerLooper?

    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }

    override func makeBackingLayer() -> CALayer {
        let l = AVPlayerLayer()
        l.videoGravity = .resizeAspect
        l.backgroundColor = NSColor.clear.cgColor
        l.isOpaque = false
        return l
    }

    override var isOpaque: Bool { false }
    override var wantsDefaultClipping: Bool { false }

    init(url: URL) {
        let asset = AVURLAsset(url: url)
        let item = AVPlayerItem(asset: asset)
        let queue = AVQueuePlayer(playerItem: item)
        queue.isMuted = true
        queue.volume = 0
        self.queuePlayer = queue
        super.init(frame: .zero)
        wantsLayer = true
        playerLayer.player = queue
        looper = AVPlayerLooper(player: queue, templateItem: item)
        queue.play()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }
}
