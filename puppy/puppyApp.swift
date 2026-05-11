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
    private var calendarService: CalendarService!
    private var calendarReminder: CalendarReminder!
    private var transcriptWatcher: TranscriptWatcher!
    private let googleAuth = GoogleAuth()

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

        calendarService = CalendarService()
        calendarReminder = CalendarReminder(service: calendarService)
        calendarReminder.onUpcomingEvent = { [weak self] event in
            self?.petWindow.showBubble("\(event.title) 일정이 있다멍")
        }
        calendarReminder.onTokenExpired = { [weak self] in
            guard let self else { return }
            self.petWindow.viewModel.calendarConnected = false
            self.petWindow.showBubble("캘린더 만료됐다멍 다시 연결해줘 🐾")
        }
        petWindow.viewModel.calendarConnected = calendarService.isConnected
        if calendarService.isConnected { calendarReminder.start() }

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
            guard let hit = self.reminder.categoryAndMessage(workedSeconds: elapsed) else { return }
            if hit.category == .remindBreak {
                // 너무 오래 일했음 → 강아지를 화면 중앙으로 끌어와 walk.mp4로 전환.
                // 사용자가 강아지를 클릭하기 전까지 유지(autoHide: 0).
                self.petWindow.showBubble(hit.message, autoHideAfter: 0)
                self.petWindow.triggerBreakAlert()
            } else {
                self.petWindow.showBubble(hit.message)
            }
        }
        workTimer.start()

        transcriptWatcher = TranscriptWatcher()
        transcriptWatcher.onThinkingChanged = { [weak self] thinking in
            guard let self, self.settings.isPetVisible else { return }
            self.petWindow.viewModel.isThinking = thinking
        }
        transcriptWatcher.onWaitingApprovalChanged = { [weak self] waiting in
            guard let self, self.settings.isPetVisible else { return }
            self.petWindow.viewModel.isWaitingApproval = waiting
        }
        transcriptWatcher.onTurnEnded = { [weak self] lastPrompt, body in
            guard let self else { return }
            guard self.settings.isPetVisible else { return }
            let snippet = lastPrompt.map { Self.truncate($0, max: 30) } ?? ""
            let msg = snippet.isEmpty ? "클코 작업 끝났다멍" : "\"\(snippet)\" 클코 작업 끝났다멍"
            self.petWindow.showBubble(msg, summary: body, autoHideAfter: 0)
        }
        transcriptWatcher.start()
    }

    private static func truncate(_ s: String, max: Int) -> String {
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count <= max { return trimmed }
        let idx = trimmed.index(trimmed.startIndex, offsetBy: max)
        return String(trimmed[..<idx]) + "…"
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationWillTerminate(_ notification: Notification) {
        workTimer?.stop()
        transcriptWatcher?.stop()
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
        petWindow.viewModel.onContextConnectCalendar = { [weak self] in
            guard let self else { return }
            Task { @MainActor in
                do {
                    let tokens = try await self.googleAuth.authenticate()
                    self.calendarService.setTokens(tokens)
                    self.petWindow.viewModel.calendarConnected = true
                    self.calendarReminder.start()
                    self.petWindow.showBubble("캘린더 연결됐다멍!")
                } catch GoogleAuthError.userCanceled {
                    // 사용자가 취소: 무시
                } catch {
                    NSLog("[Calendar] auth failed: \(error)")
                    self.petWindow.showBubble("연결 실패다멍 😢")
                }
            }
        }
        petWindow.viewModel.onContextDisconnectCalendar = { [weak self] in
            guard let self else { return }
            self.calendarService.disconnect()
            self.calendarReminder.stop()
            self.petWindow.viewModel.calendarConnected = false
            self.petWindow.showBubble("캘린더 끊었다멍")
        }
    }
}
