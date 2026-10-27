import AppKit
import Combine
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let coordinator = CaptureCoordinator()
    private let hotkeyManager = HotkeyManager()
    private var statusItem: NSStatusItem?
    private var captureItem: NSMenuItem?
    private var settingsWindowController: SettingsWindowController?
    private var hotkeySubscription: AnyCancellable?

    func applicationDidFinishLaunching(_ notification: Notification) {
        installMainMenu()
        coordinator.openSettings = { [weak self] in self?.openSettings() }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "viewfinder", accessibilityDescription: "Capture")
        item.button?.image?.isTemplate = true
        let menu = NSMenu()
        let capture = NSMenuItem(title: "Capture Area", action: #selector(captureArea), keyEquivalent: "")
        capture.target = self
        menu.addItem(capture)
        let settings = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit Capture", action: #selector(quitCapture), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
        item.menu = menu
        statusItem = item
        captureItem = capture

        hotkeySubscription = AppSettings.shared.$hotkey.removeDuplicates().sink { [weak self] hotkey in
            guard let self else { return }
            self.captureItem?.keyEquivalent = hotkey.keyEquivalent
            self.captureItem?.keyEquivalentModifierMask = hotkey.modifierMask
            // Keep uncommon keys readable even if AppKit has no key equivalent for them.
            self.captureItem?.title = hotkey.keyEquivalent.isEmpty ? "Capture Area \(hotkey.displayString)" : "Capture Area"
            self.hotkeyManager.register(hotkey) { [weak self] in self?.coordinator.startCapture() }
        }
        #if DEBUG
        DebugSnapshots.scheduleQuit()
        let defaults = UserDefaults.standard
        if defaults.bool(forKey: "debugOpenSettings") { openSettings() }
        if defaults.bool(forKey: "debugSelectionOverlay") {
            coordinator.startCapture()
        } else if let value = defaults.string(forKey: "debugCaptureRect") {
            let components = value.split(separator: ",", omittingEmptySubsequences: false)
            let parts = components.compactMap { Double($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
            if components.count == 4, parts.count == 4, parts.allSatisfy({ $0.isFinite }), parts[2] > 0, parts[3] > 0 {
                coordinator.startDebugCapture(rect: CGRect(x: parts[0], y: parts[1], width: parts[2], height: parts[3]),
                                              action: defaults.string(forKey: "debugAction"))
            }
        }
        #endif
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotkeyManager.unregister()
    }

    @objc private func captureArea() {
        coordinator.startCapture()
    }

    @objc private func openSettings() {
        if settingsWindowController == nil {
            settingsWindowController = SettingsWindowController(settings: .shared)
            settingsWindowController?.onClose = { [weak self] in self?.coordinator.settingsDidClose() }
        }
        if let window = settingsWindowController?.window, !window.isVisible {
            coordinator.prepareSettings(window: window)
        }
        settingsWindowController?.show()
    }

    private func installMainMenu() {
        let mainMenu = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About Capture", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit Capture", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        mainMenu.addItem(appItem)

        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        for (title, action, key, modifiers) in [
            ("Undo", "undo:", "z", NSEvent.ModifierFlags.command),
            ("Redo", "redo:", "z", [.command, .shift]),
            ("Cut", "cut:", "x", .command),
            ("Copy", "copy:", "c", .command),
            ("Paste", "paste:", "v", .command),
            ("Select All", "selectAll:", "a", .command)
        ] {
            let item = NSMenuItem(title: title, action: NSSelectorFromString(action), keyEquivalent: key)
            item.keyEquivalentModifierMask = modifiers
            editMenu.addItem(item)
        }
        editItem.submenu = editMenu
        mainMenu.addItem(editItem)
        NSApp.mainMenu = mainMenu
    }

    @objc private func quitCapture() {
        NSApp.terminate(nil)
    }
}
