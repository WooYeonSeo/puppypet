import AppKit

final class StatusBarController: NSObject {
    private let statusItem: NSStatusItem
    private let menu = NSMenu()

    var onShow: (() -> Void)?
    var onHide: (() -> Void)?
    var onToggleReminders: ((Bool) -> Void)?
    var onResetTimer: (() -> Void)?
    var onQuit: (() -> Void)?

    private var isPetVisible: Bool = true
    private var remindersEnabled: Bool = true
    private var intervalMinutes: Int = 25

    override init() {
        self.statusItem = NSStatusBar.system.statusItem(withLength: 28)
        super.init()
        statusItem.isVisible = true
        configureButton()
        rebuildMenu()
        statusItem.menu = menu
    }

    func setState(petVisible: Bool, remindersEnabled: Bool, intervalMinutes: Int) {
        self.isPetVisible = petVisible
        self.remindersEnabled = remindersEnabled
        self.intervalMinutes = intervalMinutes
        rebuildMenu()
    }

    private func configureButton() {
        guard let button = statusItem.button else { return }
        // SF Symbol이 이모지보다 메뉴바에서 안정적으로 렌더링됨
        if let image = NSImage(systemSymbolName: "pawprint.fill", accessibilityDescription: "PuppyPet") {
            image.isTemplate = true
            button.image = image
        } else {
            button.title = "🐶"
        }
        button.toolTip = "PuppyPet"
    }

    private func rebuildMenu() {
        menu.removeAllItems()

        let showItem = NSMenuItem(title: "Show Puppy", action: #selector(showAction), keyEquivalent: "")
        showItem.target = self
        showItem.state = isPetVisible ? .on : .off
        menu.addItem(showItem)

        let hideItem = NSMenuItem(title: "Hide Puppy", action: #selector(hideAction), keyEquivalent: "")
        hideItem.target = self
        hideItem.state = isPetVisible ? .off : .on
        menu.addItem(hideItem)

        menu.addItem(.separator())

        let reminderItem = NSMenuItem(
            title: "Reminders: \(remindersEnabled ? "On" : "Off")",
            action: #selector(toggleRemindersAction),
            keyEquivalent: ""
        )
        reminderItem.target = self
        reminderItem.state = remindersEnabled ? .on : .off
        menu.addItem(reminderItem)

        let intervalLabel = NSMenuItem(
            title: "Remind Every: \(intervalMinutes) min",
            action: nil,
            keyEquivalent: ""
        )
        intervalLabel.isEnabled = false
        menu.addItem(intervalLabel)

        let resetItem = NSMenuItem(title: "Reset Timer", action: #selector(resetAction), keyEquivalent: "")
        resetItem.target = self
        menu.addItem(resetItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit", action: #selector(quitAction), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
    }

    @objc private func showAction() { onShow?() }
    @objc private func hideAction() { onHide?() }
    @objc private func toggleRemindersAction() { onToggleReminders?(!remindersEnabled) }
    @objc private func resetAction() { onResetTimer?() }
    @objc private func quitAction() { onQuit?() }
}
