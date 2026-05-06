import Foundation

final class WorkTimer {
    private(set) var startedAt: Date = Date()
    private var timer: Timer?
    private let tickInterval: TimeInterval
    var onTick: ((TimeInterval) -> Void)?

    init(tickInterval: TimeInterval = 60) {
        self.tickInterval = tickInterval
    }

    func start() {
        stop()
        startedAt = Date()
        let t = Timer(timeInterval: tickInterval, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.onTick?(Date().timeIntervalSince(self.startedAt))
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func reset() {
        startedAt = Date()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    var elapsedSeconds: TimeInterval {
        Date().timeIntervalSince(startedAt)
    }
}
