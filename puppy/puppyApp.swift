import AppKit
import SwiftUI

@main
enum PuppyMain {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var settings: SettingsStore!
    private var statusBar: StatusBarController!
    private var petWindow: PetWindowController!
    private var workTimer: WorkTimer!
    private var reminder: ReminderEngine!

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        settings = SettingsStore()
        reminder = ReminderEngine(intervalMinutes: settings.reminderIntervalMinutes)
        petWindow = PetWindowController(settings: settings)
        workTimer = WorkTimer(tickInterval: 60)
        statusBar = StatusBarController()

        if settings.isPetVisible {
            petWindow.show()
        } else {
            petWindow.hide()
        }
        petWindow.viewModel.remindersEnabled = settings.remindersEnabled
        wirePetContextMenu()
        applyMenuState()

        if let panel = NSApp.windows.first(where: { $0 is PetPanel }) {
            NSLog("[PuppyPet] PetPanel ok: frame=\(panel.frame) visible=\(panel.isVisible) level=\(panel.level.rawValue) opaque=\(panel.isOpaque)")
        } else {
            NSLog("[PuppyPet] PetPanel NOT in NSApp.windows!")
        }
        NSLog("[PuppyPet] NSScreen.main visibleFrame: \(NSScreen.main?.visibleFrame ?? .zero)")

        statusBar.onShow = { [weak self] in
            guard let self else { return }
            self.settings.isPetVisible = true
            self.petWindow.show()
            self.applyMenuState()
        }
        statusBar.onHide = { [weak self] in
            guard let self else { return }
            self.settings.isPetVisible = false
            self.petWindow.hide()
            self.applyMenuState()
        }
        statusBar.onToggleReminders = { [weak self] newValue in
            guard let self else { return }
            self.settings.remindersEnabled = newValue
            self.applyMenuState()
        }
        statusBar.onResetTimer = { [weak self] in
            self?.workTimer.reset()
            self?.reminder.resetTimer()
        }
        statusBar.onQuit = {
            NSApp.terminate(nil)
        }

        workTimer.onTick = { [weak self] elapsed in
            guard let self else { return }
            guard self.settings.remindersEnabled else { return }
            if let hit = self.reminder.categoryAndMessage(workedSeconds: elapsed) {
                self.petWindow.showBubble(hit.message)
            }
        }
        workTimer.start()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationWillTerminate(_ notification: Notification) {
        workTimer?.stop()
    }

    private func applyMenuState() {
        statusBar.setState(
            petVisible: settings.isPetVisible,
            remindersEnabled: settings.remindersEnabled,
            intervalMinutes: settings.reminderIntervalMinutes
        )
    }

    private func wirePetContextMenu() {
        petWindow.viewModel.onContextToggleReminders = { [weak self] in
            guard let self else { return }
            let newValue = !self.settings.remindersEnabled
            self.settings.remindersEnabled = newValue
            self.petWindow.viewModel.remindersEnabled = newValue
            self.applyMenuState()
        }
        petWindow.viewModel.onContextResetTimer = { [weak self] in
            self?.workTimer.reset()
            self?.reminder.resetTimer()
        }
        petWindow.viewModel.onContextHide = { [weak self] in
            guard let self else { return }
            self.settings.isPetVisible = false
            self.petWindow.hide()
            self.applyMenuState()
        }
        petWindow.viewModel.onContextQuit = {
            NSApp.terminate(nil)
        }
    }
}
