import AppKit
import Combine
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let coordinator = CaptureCoordinator()
    private let documentReader = DocumentTextController()
    private let hotkeyManager = HotkeyManager()
    private let documentHotkeyManager = HotkeyManager(id: 2)
    private var statusItem: NSStatusItem?
    private var captureItem: NSMenuItem?
    private var settingsWindowController: SettingsWindowController?
    private var hotkeySubscription: AnyCancellable?
    private var apiKeySubscription: AnyCancellable?

    func applicationDidFinishLaunching(_ notification: Notification) {
        installMainMenu()
        coordinator.openSettings = { [weak self] in self?.openSettings() }
        apiKeySubscription = AppSettings.shared.$apiKeyRequired.dropFirst().sink { [weak self] required in
            guard required else { return }
            Task { @MainActor [weak self] in self?.openSettings() }
        }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "viewfinder", accessibilityDescription: "Capture")
        item.button?.image?.isTemplate = true
        let menu = NSMenu()
        let capture = NSMenuItem(title: "Capture Area", action: #selector(captureArea), keyEquivalent: "")
        capture.target = self
        menu.addItem(capture)
        let readText = NSMenuItem(title: "Read Active Document Text", action: #selector(readDocumentText), keyEquivalent: Hotkey.documentText.keyEquivalent)
        readText.keyEquivalentModifierMask = Hotkey.documentText.modifierMask
        readText.target = self
        menu.addItem(readText)
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

        hotkeySubscription = AppSettings.shared.$hotkey.combineLatest(AppSettings.shared.$documentHotkey)
            .sink { [weak self] hotkey, documentHotkey in
                guard let self else { return }
                self.captureItem?.keyEquivalent = hotkey.keyEquivalent
                self.captureItem?.keyEquivalentModifierMask = hotkey.modifierMask
                self.captureItem?.title = hotkey.keyEquivalent.isEmpty ? "Capture Area \(hotkey.displayString)" : "Capture Area"
                self.hotkeyManager.unregister()
                self.documentHotkeyManager.unregister()
                let captureRegistered = self.hotkeyManager.register(hotkey) { [weak self] in self?.coordinator.startCapture() }
                readText.keyEquivalent = documentHotkey == hotkey ? "" : documentHotkey.keyEquivalent
                readText.keyEquivalentModifierMask = documentHotkey.modifierMask
                let textRegistered = documentHotkey != hotkey && self.documentHotkeyManager.register(documentHotkey) {
                    [weak self] in self?.readDocumentText()
                }
                var errors: [String] = []
                if !captureRegistered { errors.append("Capture shortcut is unavailable. Choose another shortcut.") }
                if !textRegistered { errors.append("Document text shortcut is unavailable or conflicts with capture. Choose another shortcut, or use the menu command.") }
                AppSettings.shared.hotkeyError = errors.isEmpty ? nil : errors.joined(separator: "\n")
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
        documentHotkeyManager.unregister()
    }

    @objc private func readDocumentText() {
        documentReader.read(openSettings: { [weak self] in self?.openSettings() },
                            captureArea: { [weak self] in self?.coordinator.startCapture() })
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
