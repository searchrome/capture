import AppKit

@MainActor
final class CaptureSessionUI {
    private var highlight: SelectionHighlight?
    private var bar: FloatingPanel?
    private var keyMonitor: Any?
    private var mouseMonitor: Any?
    private var resultPanel: ResultPanel?
    private var translationOverlay: TranslationOverlay?
    private var chatPanel: ChatPanel?
    private var hiddenForSettings: [NSWindow]?
    private let extractText: () -> Void
    private let translate: () -> Void
    private let openChat: () -> Void
    private let openSettings: () -> Void

    init(
        extractText: @escaping () -> Void, translate: @escaping () -> Void,
        openChat: @escaping () -> Void, openSettings: @escaping () -> Void
    ) {
        self.extractText = extractText
        self.translate = translate
        self.openChat = openChat
        self.openSettings = openSettings
    }

    func show(for capture: CaptureResult) {
        dismiss()
        guard
            let screen = NSScreen.screens.first(where: { $0.captureDisplayID == capture.displayID })
                ?? FloatingPanel.screen(containing: capture.rect)
        else { return }
        let highlight = SelectionHighlight(selection: capture.rect)
        let content = ActionBar(
            settings: .shared, extractText: extractText, translate: translate,
            openChat: openChat, openSettings: openSettings,
            close: { [weak self] in self?.dismiss() })
        let bar = FloatingPanel(
            frame: ActionBar.frame(for: capture.rect, visibleFrame: screen.visibleFrame),
            content: content)
        #if DEBUG
        bar.identifier = NSUserInterfaceItemIdentifier("debugActionBar")
        #endif
        bar.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 3)
        self.highlight = highlight
        self.bar = bar
        highlight.orderFrontRegardless()
        bar.orderFrontRegardless()
        #if DEBUG
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { DebugSnapshots.write(name: "bar") }
        #endif
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53 else { return event }
            guard let self else { return event }
            if NSApp.keyWindow?.title == "Capture Settings" { return event }
            if self.chatPanel?.isKey == true {
                self.chatPanel?.stop()
                return nil
            }
            if self.resultPanel?.isKey == true && self.translationOverlay == nil { return nil }
            self.dismiss()
            return nil
        }
        mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) {
            [weak self] event in
            guard let self, self.chatPanel?.preventsOutsideDismissal != true else { return }
            guard let cgEvent = event.cgEvent,
                  cgEvent.getIntegerValueField(.eventSourceUserData) != InputSynthesizer.syntheticEventMarker else { return }
            let point = cgEvent.location
            let appKitPoint = CGPoint(x: point.x, y: (NSScreen.screens.first?.frame.height ?? 0) - point.y)
            guard !NSApp.windows.contains(where: { $0.isVisible && $0.frame.contains(appKitPoint) }) else { return }
            self.dismiss()
        }
    }

    func showResult(
        for capture: CaptureResult, title: String, model: String,
        stream: AsyncThrowingStream<String, Error>, openChat: @escaping (String) -> Void
    ) {
        if resultPanel == nil {
            resultPanel = ResultPanel(settings: .shared, openSettings: openSettings, openChat: openChat)
        }
        resultPanel?.show(capture: capture, avoiding: chatPanel?.frame, title: title, model: model, stream: stream)
        hideNewWindowsForSettings()
    }

    func dismissTranslationOverlay() {
        translationOverlay?.close()
        translationOverlay = nil
    }

    func showTranslationOverlay(for capture: CaptureResult, openChat: @escaping (String) -> Void) {
        dismissTranslationOverlay()
        resultPanel?.close()
        resultPanel = nil
        let settings = AppSettings.shared
        let target = settings.targetLanguage
        let model = settings.visionModel
        let overlay = TranslationOverlay(capture: capture, settings: settings, openSettings: openSettings,
            openText: { [weak self] text in
                let stream = AsyncThrowingStream<String, Error> { continuation in
                    continuation.yield(text); continuation.finish()
                }
                self?.showResult(for: capture, title: "Translation → \(target)", model: model,
                                 stream: stream, openChat: openChat)
            }, fallback: { [weak self] in
                self?.showResult(for: capture, title: "Translation → \(target) · No text found; using image",
                                 model: model, stream: Translator(settings: settings).translate(from: capture),
                                 openChat: openChat)
            })
        translationOverlay = overlay
        overlay.show()
        hideNewWindowsForSettings()
    }

    func showChat(for capture: CaptureResult, seed: String?) {
        if chatPanel == nil { chatPanel = ChatPanel(capture: capture, seed: seed) }
        chatPanel?.show(avoiding: resultPanel?.frame)
        hideNewWindowsForSettings()
    }

    private var windows: [NSWindow] {
        [highlight, bar, resultPanel?.window, chatPanel?.window].compactMap { $0 }
            + (translationOverlay?.windows ?? [])
    }

    var visibleFrames: [CGRect] { windows.filter(\.isVisible).map(\.frame) }
    var hasSession: Bool { !windows.isEmpty }

    func hideForSettings() {
        guard hiddenForSettings == nil else { return }
        hiddenForSettings = []
        hideNewWindowsForSettings()
    }

    private func hideNewWindowsForSettings() {
        guard hiddenForSettings != nil else { return }
        for window in windows where window.isVisible {
            hiddenForSettings?.append(window)
            window.orderOut(nil)
        }
    }

    func restoreAfterSettings() {
        let currentWindows = windows
        for window in hiddenForSettings ?? [] where currentWindows.contains(where: { $0 === window }) {
            window.orderFrontRegardless()
        }
        hiddenForSettings = nil
    }

    #if DEBUG
        func sendDebugChatMessage(_ text: String) { chatPanel?.send(text) }
    #endif

    func dismiss() {
        hiddenForSettings = nil
        dismissTranslationOverlay()
        chatPanel?.close()
        chatPanel = nil
        resultPanel?.close()
        resultPanel = nil
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
        if let mouseMonitor { NSEvent.removeMonitor(mouseMonitor) }
        mouseMonitor = nil
        bar?.orderOut(nil)
        bar?.close()
        bar = nil
        highlight?.orderOut(nil)
        highlight?.close()
        highlight = nil
    }
}
