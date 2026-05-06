import Foundation
import CoreGraphics

final class SettingsStore {
    private enum Key {
        static let isPetVisible = "isPetVisible"
        static let remindersEnabled = "remindersEnabled"
        static let reminderIntervalMinutes = "reminderIntervalMinutes"
        static let petWindowX = "petWindowX"
        static let petWindowY = "petWindowY"
        static let hasOrigin = "hasPetWindowOrigin"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            Key.isPetVisible: true,
            Key.remindersEnabled: true,
            Key.reminderIntervalMinutes: 25,
            Key.hasOrigin: false
        ])
    }

    var isPetVisible: Bool {
        get { defaults.bool(forKey: Key.isPetVisible) }
        set { defaults.set(newValue, forKey: Key.isPetVisible) }
    }

    var remindersEnabled: Bool {
        get { defaults.bool(forKey: Key.remindersEnabled) }
        set { defaults.set(newValue, forKey: Key.remindersEnabled) }
    }

    var reminderIntervalMinutes: Int {
        get { defaults.integer(forKey: Key.reminderIntervalMinutes) }
        set { defaults.set(max(1, newValue), forKey: Key.reminderIntervalMinutes) }
    }

    var petWindowOrigin: CGPoint? {
        get {
            guard defaults.bool(forKey: Key.hasOrigin) else { return nil }
            return CGPoint(
                x: defaults.double(forKey: Key.petWindowX),
                y: defaults.double(forKey: Key.petWindowY)
            )
        }
        set {
            if let p = newValue {
                defaults.set(true, forKey: Key.hasOrigin)
                defaults.set(p.x, forKey: Key.petWindowX)
                defaults.set(p.y, forKey: Key.petWindowY)
            } else {
                defaults.set(false, forKey: Key.hasOrigin)
            }
        }
    }
}
