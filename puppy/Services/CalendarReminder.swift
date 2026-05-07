import Foundation

/// 1분 주기로 캘린더 polling, 시작 10분 전 일정에 대해 콜백.
final class CalendarReminder {
    private let service: CalendarService
    private var timer: Timer?
    private var firedEventIDs: Set<String> = []
    var onUpcomingEvent: ((CalendarEvent) -> Void)?

    init(service: CalendarService) {
        self.service = service
    }

    func start() {
        stop()
        let t = Timer(timeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.tick() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
        Task { @MainActor in await tick() }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        firedEventIDs.removeAll()
    }

    private func tick() async {
        guard service.isConnected else { return }
        do {
            let events = try await service.upcomingEvents(within: 15 * 60)
            let now = Date()
            var stillUpcoming: Set<String> = []
            for event in events {
                let secondsUntil = event.start.timeIntervalSince(now)
                stillUpcoming.insert(event.id)
                // 9분 30초 ~ 11분 사이에 시작하는 일정 알림 (1분 polling이라 9~11분 윈도우 안전)
                if secondsUntil >= 9 * 60 + 30, secondsUntil <= 11 * 60 {
                    if !firedEventIDs.contains(event.id) {
                        firedEventIDs.insert(event.id)
                        onUpcomingEvent?(event)
                    }
                }
            }
            // 끝나거나 사라진 이벤트 ID 정리
            firedEventIDs = firedEventIDs.intersection(stillUpcoming)
        } catch {
            NSLog("[Calendar] fetch error: \(error)")
        }
    }
}
