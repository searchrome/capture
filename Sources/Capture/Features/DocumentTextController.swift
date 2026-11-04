import AppKit
import ApplicationServices

@MainActor
final class DocumentTextController {
    private var panel: ResultPanel?

    func read(openSettings: @escaping () -> Void, captureArea: @escaping () -> Void) {
        // Resolve the target before our result panel takes keyboard focus.
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier else {
            let alert = NSAlert()
            alert.messageText = "Choose a Document Window"
            alert.informativeText = "Focus the webpage or document you want to read, then choose Read Active Document Text from Capture’s menu."
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
            return
        }
        let trusted = AXIsProcessTrustedWithOptions(
            [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary)
        guard trusted else {
            let alert = NSAlert()
            alert.messageText = "Allow Accessibility Access"
            alert.informativeText = "Enable Capture in System Settings → Privacy & Security → Accessibility, then try again. This lets Capture read text exposed by the active document."
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
            return
        }
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let anchor = CGRect(x: screen.frame.midX, y: (NSScreen.screens.first?.frame.height ?? 0) - screen.frame.midY,
                            width: 1, height: 1)
        let pid = app.processIdentifier
        let name = app.localizedName ?? "Document"
        let stream = AsyncThrowingStream<String, Error> { continuation in
            let task = Task.detached(priority: .userInitiated) {
                do {
                    let output = try DocumentTextReader().read(pid: pid)
                    try Task.checkCancellation()
                    continuation.yield(output.text)
                    if output.isPartial {
                        throw DocumentTextReader.ReadError(message: "Only part of the exposed text was read before the read limit was reached. You can copy this text or capture an area instead.")
                    }
                    continuation.finish()
                } catch { continuation.finish(throwing: error) }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
        panel?.close()
        let result = ResultPanel(settings: .shared, openSettings: openSettings, openChat: nil, captureArea: { [weak self] in
            self?.panel?.close()
            captureArea()
        })
        panel = result
        result.show(rect: anchor, displayID: screen.captureDisplayID ?? CGMainDisplayID(), title: "Document Text · \(name)",
                    model: "Local · no AI request", stream: stream)
    }
}
