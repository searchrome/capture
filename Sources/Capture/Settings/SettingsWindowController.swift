import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    var onClose: () -> Void = {}
    init(settings: AppSettings) {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 640),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: false)
        window.title = "Capture Settings"
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 480, height: 400)
        window.contentView = NSHostingView(rootView: SettingsView(settings: settings))
        window.center()
        super.init(window: window)
        window.delegate = self
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func windowWillClose(_ notification: Notification) { onClose() }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        #if DEBUG
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { DebugSnapshots.write(name: "settings") }
        #endif
    }
}
