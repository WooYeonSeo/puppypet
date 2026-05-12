import SwiftUI
import AppKit
import Combine

final class PetViewModel: ObservableObject {
    @Published var bubbleText: String?
    @Published var isDragging: Bool = false
    @Published var remindersEnabled: Bool = true
    @Published var calendarConnected: Bool = false
    @Published var isThinking: Bool = false
    @Published var isWaitingApproval: Bool = false
    /// 휴식 권장 알림 전체 상태(이동 + 도착 + 사용자 클릭 대기 포함).
    @Published var isBreakAlert: Bool = false
    /// 실제로 walk 영상이 재생되어야 하는 짧은 구간(왼쪽으로 걸어가는 중, 또는
    /// 원위치로 돌아가는 중). 도착하면 false로 돌아가 일반 영상으로 전환.
    @Published var isWalking: Bool = false
    /// walk 영상이 오른쪽으로 진행 중이면 true → horizontal flip 적용해 자연스럽게.
    @Published var isWalkFlipped: Bool = false
    @Published var summaryBody: String?
    @Published var isShowingSummary: Bool = false
    var onDragBegan: (() -> Void)?
    var onDragEnded: ((CGPoint) -> Void)?
    /// 휴식 권장 알림 상태에서 강아지를 클릭하면 호출되어 윈도우 위치를 복원하고
    /// 일반 영상으로 되돌릴 수 있게 한다.
    var onBreakAlertDismissTap: (() -> Void)?

    // 우클릭 컨텍스트 메뉴 액션
    var onContextToggleReminders: (() -> Void)?
    var onContextResetTimer: (() -> Void)?
    var onContextHide: (() -> Void)?
    var onContextQuit: (() -> Void)?
    var onContextConnectCalendar: (() -> Void)?
    var onContextDisconnectCalendar: (() -> Void)?
    var onContextTodaySchedule: (() -> Void)?

    private var bubbleTask: Task<Void, Never>?
    /// Sticky 말풍선(autoHideAfter == 0)이 떠 있는 동안에는 일반(자동 사라짐)
    /// 말풍선이 덮어쓰지 못하도록 막는다. 사용자가 직접 닫기 전까지 유지.
    private var isStickyBubble: Bool = false
    /// popover가 한 번이라도 열렸는지 추적. SwiftUI popover는 바깥쪽 클릭으로
    /// 자동 닫혀 `isShowingSummary`를 false로 되돌리는데, 그 직후 사용자가
    /// 말풍선을 탭하면 "재오픈"이 아니라 "전체 닫기"여야 하기 때문에 별도 플래그로
    /// 1회 오픈 이력을 보존한다.
    private var popoverOpened: Bool = false

    func showBubble(_ text: String, summary: String? = nil, autoHideAfter seconds: TimeInterval = 5) {
        // 사용자가 닫지 않은 sticky 말풍선이 있으면 transient 알림은 무시.
        // (sticky → sticky 갱신은 허용: 새 Claude Code 완료 알림이 더 최신 정보)
        if isStickyBubble && seconds > 0 { return }

        bubbleTask?.cancel()
        bubbleText = text
        summaryBody = summary
        isShowingSummary = false
        popoverOpened = false
        isStickyBubble = (seconds == 0)
        guard seconds > 0 else { return }
        bubbleTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            if Task.isCancelled { return }
            await MainActor.run { [weak self] in
                if self?.bubbleText == text { self?.bubbleText = nil }
            }
        }
    }

    func clearBubble() {
        bubbleTask?.cancel()
        bubbleText = nil
        summaryBody = nil
        isShowingSummary = false
        isStickyBubble = false
        popoverOpened = false
    }

    /// 탭 동작:
    ///   • summary 없음 → 즉시 닫기
    ///   • summary 있고 popover 한 번도 안 열림 → popover 열기 (본문 확인)
    ///   • summary 있고 popover가 열렸던 적 있음 → 전체 닫기
    func handleBubbleTap() {
        if summaryBody == nil {
            clearBubble()
            return
        }
        if popoverOpened {
            clearBubble()
        } else {
            isShowingSummary = true
            popoverOpened = true
        }
    }

    func beginDragging() {
        isDragging = true
        onDragBegan?()
    }

    func endDragging(at origin: CGPoint) {
        isDragging = false
        onDragEnded?(origin)
    }

    /// 강아지 머리 위 표시 우선순위:
    /// 권한 대기(🔔) > 일반 작업 중(💭) > 없음.
    var thinkingIndicator: String? {
        if isWaitingApproval { return "🔔" }
        if isThinking { return "💭" }
        return nil
    }
}

struct PetView: View {
    @ObservedObject var viewModel: PetViewModel

    // NSEvent.mouseLocation = 화면 절대 좌표(bottom-left). 윈도우가 이동해도 영향 없음.
    @State private var dragStartMouse: CGPoint?
    @State private var dragStartWindowOrigin: CGPoint?
    @State private var maxDragDistance: CGFloat = 0
    @State private var lastBark: String?

    // walkdog.png sprite sheet (4 columns x 2 rows = 8 frames)을 한 번만 로드해 재사용
    @State private var dogFrames: [NSImage] = []

    // 추후 PNG sprite 교체 가이드:
    // 1) Assets.xcassets에 dog_idle_0, dog_idle_1, dog_bark_0 ... 등록
    // 2) 아래 Text("🐶")를 Image("dog_idle_0").resizable().interpolation(.none) 로 교체
    // 3) TimelineView(.animation(minimumInterval: 0.25)) 로 프레임 순환

    var body: some View {
        VStack(spacing: 0) {
            // 말풍선 + 💭 영역 (고정 높이 60pt → 강아지 위치 흔들림 방지)
            //   • 💭는 ZStack 바닥에 고정 → 강아지 머리 바로 위에 표시
            //   • 말풍선은 평소엔 강아지 머리 근처(offset 30)로 내리고,
            //     💭가 뜰 땐 위로 밀어 올려(offset -28) 겹침을 방지
            ZStack(alignment: .bottom) {
                // 권한 대기(🔔) > 일반 thinking(💭) 우선순위.
                // 권한 대기는 즉시 사용자 주의가 필요해 더 강한 상징을 사용.
                if let indicator = viewModel.thinkingIndicator {
                    Text(indicator)
                        .font(.system(size: 24))
                        // 강아지 머리에 살짝 걸쳐 보이도록 dog frame 쪽으로 끌어내림
                        .offset(y: 32)
                        .transition(.opacity.combined(with: .scale(scale: 0.7)))
                }
                if let bubble = viewModel.bubbleText {
                    SpeechBubbleView(text: bubble)
                        .offset(y: viewModel.thinkingIndicator != nil ? -15 : 30)
                        .onTapGesture { viewModel.handleBubbleTap() }
                        .popover(isPresented: $viewModel.isShowingSummary, arrowEdge: .top) {
                            SummaryPopover(text: viewModel.summaryBody ?? "")
                        }
                        .transition(.opacity.combined(with: .scale(scale: 0.9)))
                }
            }
            .frame(height: 140, alignment: .bottom)

            // 강아지: 걸어가는 중일 때만 walk_alpha.mov, 그 외엔 puppy_alpha.mov.
            // 도착하면 isWalking=false로 바뀌어 일반 서있는 영상으로 자연스럽게 전환.
            // `.id`로 LoopingVideoView를 강제 재생성해야 영상이 실제로 바뀜.
            Group {
                if let videoURL = Self.locatePuppyVideo(walking: viewModel.isWalking) {
                    LoopingVideoView(url: videoURL)
                        .id(videoURL)
                } else if !dogFrames.isEmpty {
                    WalkingDogView(frames: dogFrames, fps: 8)
                } else {
                    Text("🐶").font(.system(size: 80))
                }
            }
            .frame(width: 180, height: 220)
            // 걷는 영상이 한 방향만 표현되므로, 반대 방향(=오른쪽 걸음)일 때만 좌우 반전.
            .scaleEffect(x: (viewModel.isWalking && viewModel.isWalkFlipped) ? -1 : 1, y: 1)
            .contentShape(Rectangle())
            .onAppear {
                if dogFrames.isEmpty {
                    dogFrames = SpriteSheet.loadFrames(name: "walkdog", columns: 4, rows: 2)
                }
            }
            .gesture(dragGesture)
                .contextMenu {
                    Button(viewModel.remindersEnabled ? "Reminders: On ✓" : "Reminders: Off") {
                        viewModel.onContextToggleReminders?()
                    }
                    Button("Reset Timer") {
                        viewModel.onContextResetTimer?()
                    }
                    Divider()
                    if viewModel.calendarConnected {
                        Button("Google 캘린더 연결 해제") {
                            viewModel.onContextDisconnectCalendar?()
                        }
                    } else {
                        Button("Google 캘린더 연결") {
                            viewModel.onContextConnectCalendar?()
                        }
                    }
                    Button("오늘 일정 알려줘") {
                        viewModel.onContextTodaySchedule?()
                    }
                    Divider()
                    Button("Hide Puppy") {
                        viewModel.onContextHide?()
                    }
                    Divider()
                    Button("Quit PuppyPet") {
                        viewModel.onContextQuit?()
                    }
                }
        }
        .frame(width: 200, height: 380)
        .animation(.easeInOut(duration: 0.2), value: viewModel.bubbleText)
        .animation(.easeInOut(duration: 0.25), value: viewModel.isThinking)
        .animation(.easeInOut(duration: 0.25), value: viewModel.isWaitingApproval)
        .animation(.easeInOut(duration: 0.3), value: viewModel.isBreakAlert)
    }

    /// 직전과 다른 메시지를 랜덤으로 골라서 같은 멘트 연속 출력 방지.
    private func pickBark() -> String {
        let pool = PetMessages.onClick.filter { $0 != lastBark }
        return pool.randomElement() ?? PetMessages.onClick.first ?? "멍!"
    }

    /// 걷는 중이면 walk_alpha.mov → walk.mp4 순으로,
    /// 그 외엔 puppy_alpha.mov → puppy_move.mp4 순으로 fallback.
    private static func locatePuppyVideo(walking: Bool) -> URL? {
        if walking {
            if let walkAlpha = Bundle.main.url(forResource: "walk_alpha", withExtension: "mov") {
                return walkAlpha
            }
            if let walk = Bundle.main.url(forResource: "walk", withExtension: "mp4") {
                return walk
            }
        }
        if let alpha = Bundle.main.url(forResource: "puppy_alpha", withExtension: "mov") { return alpha }
        if let mp4 = Bundle.main.url(forResource: "puppy_move", withExtension: "mp4") { return mp4 }
        return nil
    }

    private var dragGesture: some Gesture {
        // SwiftUI DragGesture의 .global은 panel 내부 좌표계라 panel 이동 시 좌표가 같이 흔들려
        // 가속 드리프트가 발생함. translation/value는 무시하고 NSEvent.mouseLocation(화면 절대 좌표)만 사용.
        DragGesture(minimumDistance: 0, coordinateSpace: .global)
            .onChanged { _ in
                guard let window = NSApp.windows.first(where: { $0 is PetPanel }) else { return }
                if dragStartMouse == nil {
                    dragStartMouse = NSEvent.mouseLocation
                    dragStartWindowOrigin = window.frame.origin
                    viewModel.beginDragging()
                }
                guard let startMouse = dragStartMouse,
                      let startWindow = dragStartWindowOrigin else { return }
                let current = NSEvent.mouseLocation
                let dx = current.x - startMouse.x
                let dy = current.y - startMouse.y
                maxDragDistance = max(maxDragDistance, hypot(dx, dy))
                // 둘 다 bottom-left 화면 좌표 → 그대로 더함. 부호 반전 필요 없음.
                let rawOrigin = CGPoint(x: startWindow.x + dx, y: startWindow.y + dy)
                // 연결된 모든 화면의 union 안으로만 clamp → 멀티 모니터/외부 디스플레이
                // 위에서도 자유롭게 드래그 가능, 완전 off-screen만 차단.
                let union: CGRect = NSScreen.screens.isEmpty
                    ? (window.screen?.frame ?? CGRect(x: 0, y: 0, width: 1440, height: 900))
                    : NSScreen.screens.reduce(.null) { $0.union($1.frame) }
                let clamped = ScreenClamp.clamp(
                    origin: rawOrigin,
                    size: window.frame.size,
                    into: union
                )
                window.setFrameOrigin(clamped)
            }
            .onEnded { _ in
                let wasClick = maxDragDistance < 5
                maxDragDistance = 0
                dragStartMouse = nil
                dragStartWindowOrigin = nil
                guard let window = NSApp.windows.first(where: { $0 is PetPanel }) else { return }
                viewModel.endDragging(at: window.frame.origin)
                if wasClick {
                    if viewModel.isBreakAlert {
                        // 휴식 알림 중에는 클릭이 "확인" 의미 → 윈도우 복귀 + 영상 복원
                        viewModel.onBreakAlertDismissTap?()
                    } else {
                        let message = pickBark()
                        lastBark = message
                        viewModel.showBubble(message)
                    }
                }
            }
    }
}
