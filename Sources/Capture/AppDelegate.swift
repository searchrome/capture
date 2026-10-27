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
        if let value = defaults.string(forKey: "debugCaptureRect") {
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
        }
        settingsWindowController?.show()
    }

    @objc private func quitCapture() {
        NSApp.terminate(nil)
    }
}
