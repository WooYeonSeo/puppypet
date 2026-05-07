import SwiftUI
import AppKit
import Combine

final class PetViewModel: ObservableObject {
    @Published var bubbleText: String?
    @Published var isDragging: Bool = false
    @Published var remindersEnabled: Bool = true
    var onDragBegan: (() -> Void)?
    var onDragEnded: ((CGPoint) -> Void)?

    // 우클릭 컨텍스트 메뉴 액션
    var onContextToggleReminders: (() -> Void)?
    var onContextResetTimer: (() -> Void)?
    var onContextHide: (() -> Void)?
    var onContextQuit: (() -> Void)?

    private var bubbleTask: Task<Void, Never>?

    func showBubble(_ text: String, autoHideAfter seconds: TimeInterval = 5) {
        bubbleTask?.cancel()
        bubbleText = text
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
    }

    func beginDragging() {
        isDragging = true
        onDragBegan?()
    }

    func endDragging(at origin: CGPoint) {
        isDragging = false
        onDragEnded?(origin)
    }
}

struct PetView: View {
    @ObservedObject var viewModel: PetViewModel

    // NSEvent.mouseLocation = 화면 절대 좌표(bottom-left). 윈도우가 이동해도 영향 없음.
    @State private var dragStartMouse: CGPoint?
    @State private var dragStartWindowOrigin: CGPoint?
    @State private var maxDragDistance: CGFloat = 0

    // walkdog.png sprite sheet (4 columns x 2 rows = 8 frames)을 한 번만 로드해 재사용
    @State private var dogFrames: [NSImage] = []

    // 추후 PNG sprite 교체 가이드:
    // 1) Assets.xcassets에 dog_idle_0, dog_idle_1, dog_bark_0 ... 등록
    // 2) 아래 Text("🐶")를 Image("dog_idle_0").resizable().interpolation(.none) 로 교체
    // 3) TimelineView(.animation(minimumInterval: 0.25)) 로 프레임 순환

    var body: some View {
        VStack(spacing: 0) {
            // 말풍선 영역 (고정 높이로 강아지 위치 흔들림 방지, offset으로 강아지 머리 근처까지 내림)
            Group {
                if let bubble = viewModel.bubbleText {
                    SpeechBubbleView(text: bubble)
                        .offset(y: 30)
                        .transition(.opacity.combined(with: .scale(scale: 0.9)))
                } else {
                    Color.clear
                }
            }
            .frame(height: 60, alignment: .bottom)

            // 강아지: cute.mp4 영상 우선 → walkdog sprite → 이모지 순서
            Group {
                if let videoURL = Self.locatePuppyVideo() {
                    LoopingVideoView(url: videoURL)
                } else if !dogFrames.isEmpty {
                    WalkingDogView(frames: dogFrames, fps: 8)
                } else {
                    Text("🐶").font(.system(size: 80))
                }
            }
            .frame(width: 180, height: 220)
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
                    Button("Hide Puppy") {
                        viewModel.onContextHide?()
                    }
                    Divider()
                    Button("Quit PuppyPet") {
                        viewModel.onContextQuit?()
                    }
                }
        }
        .frame(width: 200, height: 300)
        .animation(.easeInOut(duration: 0.2), value: viewModel.bubbleText)
    }

    /// puppy_alpha.mov(투명 배경) 우선, 없으면 puppy_move.mp4(원본) fallback.
    private static func locatePuppyVideo() -> URL? {
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
                let newOrigin = CGPoint(x: startWindow.x + dx, y: startWindow.y + dy)
                window.setFrameOrigin(newOrigin)
            }
            .onEnded { _ in
                let wasClick = maxDragDistance < 5
                maxDragDistance = 0
                dragStartMouse = nil
                dragStartWindowOrigin = nil
                guard let window = NSApp.windows.first(where: { $0 is PetPanel }) else { return }
                viewModel.endDragging(at: window.frame.origin)
                if wasClick {
                    viewModel.showBubble("멍!")
                }
            }
    }
}
