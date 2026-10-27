import AppKit

@MainActor
final class CaptureSessionUI {
    private var highlight: SelectionHighlight?
    private var bar: FloatingPanel?
    private var keyMonitor: Any?
    private var resultPanel: ResultPanel?
    private var chatPanel: ChatPanel?
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
            if self.chatPanel?.isKey == true {
                self.chatPanel?.stop()
                return nil
            }
            if self.resultPanel?.isKey == true { return nil }
            self.dismiss()
            return nil
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
    }

    func showChat(for capture: CaptureResult, seed: String?) {
        if chatPanel == nil { chatPanel = ChatPanel(capture: capture, seed: seed) }
        chatPanel?.show(avoiding: resultPanel?.frame)
    }

    #if DEBUG
        func sendDebugChatMessage(_ text: String) { chatPanel?.send(text) }
    #endif

    func dismiss() {
        chatPanel?.close()
        chatPanel = nil
        resultPanel?.close()
        resultPanel = nil
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
        bar?.orderOut(nil)
        bar?.close()
        bar = nil
        highlight?.orderOut(nil)
        highlight?.close()
        highlight = nil
    }
}
