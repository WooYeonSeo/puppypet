import AppKit
import SwiftUI

final class PetWindowController {
    private let panel: PetPanel
    private let settings: SettingsStore
    let viewModel = PetViewModel()
    /// 휴식 알림 시작 시 저장. dismiss하면 이 위치로 강아지를 되돌린다.
    private var originBeforeBreakAlert: CGPoint?
    /// 걷기 애니메이션 진행 중인 타이머. borderless NSPanel은 animator() 프록시가
    /// 안정적으로 동작하지 않아 수동 스텝 애니메이션을 사용.
    private var walkAnimationTimer: Timer?

    static let petSize = CGSize(width: 200, height: 380)

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
            // 휴식 알림 중일 때는 사용자가 강아지를 옮겨도 정상 위치 저장을 건너뜀.
            // (dismiss 시 originBeforeBreakAlert로 복원해야 하므로)
            guard let self else { return }
            if self.viewModel.isBreakAlert { return }
            self.settings.petWindowOrigin = origin
        }
        viewModel.onBreakAlertDismissTap = { [weak self] in
            self?.dismissBreakAlert()
        }
    }

    func show() {
        panel.orderFrontRegardless()
    }

    func hide() {
        panel.orderOut(nil)
    }

    var isVisible: Bool { panel.isVisible }

    func showBubble(_ text: String, summary: String? = nil, autoHideAfter seconds: TimeInterval = 5) {
        guard !viewModel.isDragging else { return }
        viewModel.showBubble(text, summary: summary, autoHideAfter: seconds)
    }

    /// 휴식 권장 알림 — 강아지가 walk 영상을 보여주면서 화면 가로 중앙으로
    /// "걸어서" 이동. 영상이 in-place walk 애니메이션이라 패널이 가로로
    /// 슬라이드하면 자연스러운 걷기로 보임.
    /// 강아지가 이미 화면 중앙보다 왼쪽이라면 더 왼쪽으로 갈 공간이 없는 것으로 보고
    /// 영상만 전환하고 위치는 그대로 둔다.
    /// 사용자가 강아지를 클릭(드래그 아님)하면 `dismissBreakAlert()`로 복귀.
    func triggerBreakAlert() {
        // 진행 중인 walk가 있으면 취소. 재트리거 시 즉시 원위치로 스냅한 뒤 처음부터.
        walkAnimationTimer?.invalidate()
        walkAnimationTimer = nil
        if viewModel.isBreakAlert, let saved = originBeforeBreakAlert {
            panel.setFrameOrigin(saved)
        }

        let currentOrigin = panel.frame.origin
        originBeforeBreakAlert = currentOrigin
        viewModel.isBreakAlert = true
        viewModel.isWalking = false
        panel.orderFrontRegardless()

        let screen = NSScreen.main?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        let centerX = screen.midX - Self.petSize.width / 2
        // 현재 위치에서 중앙 방향으로 최대 walkDistance만큼만 걷도록 제한.
        let walkDistance: CGFloat = 200
        let toCenter = centerX - currentOrigin.x
        guard abs(toCenter) > 5 else { return }
        let signedDelta = abs(toCenter) <= walkDistance
            ? toCenter
            : (toCenter > 0 ? walkDistance : -walkDistance)
        let finalX = currentOrigin.x + signedDelta

        // 걷기 시작 → 영상도 walk로 전환. 오른쪽으로 가면 좌우 반전.
        viewModel.isWalking = true
        animateWalk(
            to: CGPoint(x: finalX, y: currentOrigin.y)
        ) { [weak self] in
            self?.viewModel.isWalking = false
        }
    }

    func dismissBreakAlert() {
        guard viewModel.isBreakAlert else { return }
        let saved = originBeforeBreakAlert
        originBeforeBreakAlert = nil

        // 원래 위치까지 walk 영상 유지하면서 걸어서 복귀 후 알림 종료.
        if let target = saved, panel.frame.origin != target {
            viewModel.isWalking = true
            animateWalk(to: target) { [weak self] in
                self?.viewModel.isWalking = false
                self?.viewModel.isBreakAlert = false
            }
        } else {
            viewModel.isBreakAlert = false
        }
    }

    /// 60fps에 가까운 타이머로 origin을 한 단계씩 옮겨 부드러운 걷기 이동 구현.
    /// borderless NSPanel에서도 안정적으로 동작.
    /// 일정한 속도(약 45pt/s)로 이동하도록 거리 기준으로 duration을 자동 산출.
    private func animateWalk(to target: CGPoint, completion: (() -> Void)?) {
        walkAnimationTimer?.invalidate()
        let start = panel.frame.origin
        // 진행 방향에 따라 영상 좌우 반전 결정 (오른쪽으로 갈 때만 flip).
        viewModel.isWalkFlipped = target.x > start.x
        let distance = hypot(target.x - start.x, target.y - start.y)
        let speed: CGFloat = 45  // pt/sec — 사용자가 OK한 페이스
        let duration = max(0.5, TimeInterval(distance / speed))
        let startTime = Date().timeIntervalSinceReferenceDate
        // Timer.scheduledTimer는 RunLoop.default 모드만 등록 → 메뉴 트래킹 등에서
        // 누락됨. 수동으로 RunLoop.main에 .common 모드로 등록해야 안정 동작.
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            let elapsed = Date().timeIntervalSinceReferenceDate - startTime
            let t = min(1.0, max(0.0, elapsed / duration))
            // 선형(linear) — 처음부터 끝까지 일정 속도로 걸어감
            let x = start.x + (target.x - start.x) * t
            let y = start.y + (target.y - start.y) * t
            self.panel.setFrameOrigin(CGPoint(x: x, y: y))
            if t >= 1.0 {
                timer.invalidate()
                self.walkAnimationTimer = nil
                completion?()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        walkAnimationTimer = timer
    }

    private static func resolveInitialOrigin(saved: CGPoint?) -> CGPoint {
        let screen = NSScreen.main
        let visible = screen?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        // 저장된 위치 복원 시에는 전체 화면 frame 안으로만 clamp (메뉴바 위 위치도 보존)
        let fullFrame = screen?.frame ?? visible
        if let saved {
            return ScreenClamp.clamp(origin: saved, size: petSize, into: fullFrame)
        }
        // 첫 실행 기본 위치는 visibleFrame 우하단(메뉴바/Dock 피해서 자연스럽게)
        return CGPoint(
            x: visible.maxX - petSize.width - 40,
            y: visible.minY + 40
        )
    }
}
