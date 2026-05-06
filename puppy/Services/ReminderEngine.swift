import Foundation

struct ReminderHit: Equatable {
    let category: ReminderCategory
    let message: String

    static func == (lhs: ReminderHit, rhs: ReminderHit) -> Bool {
        lhs.category == rhs.category && lhs.message == rhs.message
    }
}

final class ReminderEngine {
    private(set) var intervalMinutes: Int
    private var lastFiredBoundary: Int = 0

    init(intervalMinutes: Int) {
        self.intervalMinutes = max(1, intervalMinutes)
    }

    func updateInterval(_ minutes: Int) {
        intervalMinutes = max(1, minutes)
    }

    func resetTimer() {
        lastFiredBoundary = 0
    }

    func categoryAndMessage(workedSeconds: TimeInterval) -> ReminderHit? {
        let intervalSeconds = TimeInterval(intervalMinutes * 60)
        let boundary = Int(workedSeconds / intervalSeconds)
        guard boundary >= 1, boundary > lastFiredBoundary else { return nil }
        lastFiredBoundary = boundary

        let category = categoryFor(boundary: boundary)
        let pool: [String]
        switch category {
        case .bark:        pool = PetMessages.bark
        case .askWalk:     pool = PetMessages.askWalk
        case .remindBreak: pool = PetMessages.remindBreak
        }
        let message = pool.randomElement() ?? "멍?"
        return ReminderHit(category: category, message: message)
    }

    private func categoryFor(boundary: Int) -> ReminderCategory {
        switch boundary {
        case 1:  return .bark
        case 2:  return .askWalk
        default: return .remindBreak
        }
    }
}
