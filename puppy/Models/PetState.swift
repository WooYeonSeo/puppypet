import Foundation

enum PetState: Equatable {
    case idle
    case bark
    case askWalk
    case remindBreak
}

enum ReminderCategory: CaseIterable {
    case bark
    case askWalk
    case remindBreak
}
