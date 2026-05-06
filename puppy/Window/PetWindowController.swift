import AppKit
import SwiftUI

final class PetWindowController {
    private let panel: PetPanel
    private let settings: SettingsStore
    let viewModel = PetViewModel()

    static let petSize = CGSize(width: 200, height: 200)

    init(settings: SettingsStore) {
        self.settings = settings

        let initialOrigin = Self.resolveInitialOrigin(saved: settings.petWindowOrigin)
        let frame = NSRect(origin: initialOrigin, size: Self.petSize)
        self.panel = PetPanel(contentRect: frame)

        let host = NSHostingView(rootView: PetView(viewModel: viewModel))
        host.frame = NSRect(origin: .zero, size: Self.petSize)
        host.autoresizingMask = [.width, .height]
        panel.contentView = host

        viewModel.onDragEnded = { [weak self] origin in
            self?.settings.petWindowOrigin = origin
        }
    }

    func show() {
        panel.orderFrontRegardless()
    }

    func hide() {
        panel.orderOut(nil)
    }

    var isVisible: Bool { panel.isVisible }

    func showBubble(_ text: String) {
        guard !viewModel.isDragging else { return }
        viewModel.showBubble(text)
    }

    private static func resolveInitialOrigin(saved: CGPoint?) -> CGPoint {
        let visible = NSScreen.main?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        if let saved {
            return ScreenClamp.clamp(origin: saved, size: petSize, into: visible)
        }
        // 기본 위치: 우하단에서 살짝 안쪽
        return CGPoint(
            x: visible.maxX - petSize.width - 40,
            y: visible.minY + 40
        )
    }
}
