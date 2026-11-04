import AppKit
import SwiftUI

@MainActor
private final class ResultState: ObservableObject {
    @Published var title = ""
    @Published var model = ""
    @Published var text = ""
    @Published var streaming = false
    @Published var error: String?
    @Published var missingKey = false
    @Published var copied = false
}

@MainActor
final class ResultPanel: NSObject, NSWindowDelegate {
    private let state = ResultState()
    private var panel: FloatingPanel?
    private var streamTask: Task<Void, Never>?
    private var copiedTask: Task<Void, Never>?
    private let settings: AppSettings
    private let captureArea: (() -> Void)?
    private let openSettings: () -> Void
    private let openChat: ((String) -> Void)?

    init(settings: AppSettings, openSettings: @escaping () -> Void, openChat: ((String) -> Void)?, captureArea: (() -> Void)? = nil) {
        self.captureArea = captureArea
        self.settings = settings
        self.openSettings = openSettings
        self.openChat = openChat
    }

    var window: NSWindow? { panel }
    var frame: CGRect? { panel?.isVisible == true ? panel?.frame : nil }
    var isKey: Bool { panel?.isKeyWindow == true }

    func show(capture: CaptureResult, avoiding: CGRect? = nil, title: String, model: String, stream: AsyncThrowingStream<String, Error>) {
        show(rect: capture.rect, displayID: capture.displayID, avoiding: avoiding, title: title, model: model, stream: stream)
    }

    func show(rect: CGRect, displayID: CGDirectDisplayID, avoiding: CGRect? = nil, title: String, model: String,
              stream: AsyncThrowingStream<String, Error>) {
        streamTask?.cancel()
        copiedTask?.cancel()
        state.title = title
        state.model = model
        state.text = ""
        state.error = nil
        state.missingKey = false
        state.copied = false
        state.streaming = true
        if panel == nil {
            guard let screen = NSScreen.screens.first(where: { $0.captureDisplayID == displayID })
                ?? FloatingPanel.screen(containing: rect) else { return }
            let view = ResultPanelView(state: state, copy: { [weak self] in self?.copyResult() },
                                       chat: openChat == nil ? nil : { [weak self] in self?.chat() },
                                       settings: openSettings, captureArea: captureArea, close: { [weak self] in self?.close() })
            let window = FloatingPanel(frame: FloatingPanel.frameBeside(selection: rect, visibleFrame: screen.visibleFrame,
                                                                         size: CGSize(width: 420, height: 300),
                                                                         minimumSize: CGSize(width: 280, height: 160), avoiding: avoiding),
                                       titled: true, content: view)
            window.styleMask.insert(.resizable)
            window.minSize = NSSize(width: 280, height: 160)
            window.title = "Capture Result"
            window.delegate = self
            panel = window
        }
        panel?.makeKeyAndOrderFront(nil)
        streamTask = Task { [weak self] in
            guard let self else { return }
            do {
                for try await delta in stream {
                    try Task.checkCancellation()
                    self.state.text += delta
                }
                try Task.checkCancellation()
                self.state.streaming = false
                if self.settings.autoCopy && !self.state.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    self.copyResult()
                }
                #if DEBUG
                DebugSnapshots.writeText(self.state.text, file: "result.txt")
                DispatchQueue.main.async { DebugSnapshots.write(name: "result") }
                #endif
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                self.state.streaming = false
                self.state.error = error.localizedDescription
                if case OpenRouterError.missingAPIKey = error { self.state.missingKey = true }
                if error is Keychain.KeychainError { self.state.missingKey = true }
                #if DEBUG
                DebugSnapshots.writeText(error.localizedDescription, file: "result.txt")
                DispatchQueue.main.async { DebugSnapshots.write(name: "result") }
                #endif
            }
        }
    }

    func close() {
        streamTask?.cancel()
        streamTask = nil
        copiedTask?.cancel()
        panel?.close()
        panel = nil
    }

    func windowWillClose(_ notification: Notification) {
        streamTask?.cancel()
        streamTask = nil
        copiedTask?.cancel()
        panel = nil
    }

    private func copyResult() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(state.text, forType: .string)
        state.copied = true
        copiedTask?.cancel()
        copiedTask = Task { [weak self] in
            do { try await Task.sleep(nanoseconds: 1_500_000_000) } catch { return }
            self?.state.copied = false
        }
    }

    private func chat() { openChat?(state.text) }
}

@MainActor
private struct ResultPanelView: View {
    @ObservedObject var state: ResultState
    let copy: () -> Void
    let chat: (() -> Void)?
    let settings: () -> Void
    let captureArea: (() -> Void)?
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(state.title).font(.headline)
                Spacer()
                Text(state.model).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                if state.streaming { ProgressView().controlSize(.small) }
            }
            TextEditor(text: $state.text)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .border(Color.secondary.opacity(0.25))
            if let error = state.error {
                HStack {
                    Text(error).foregroundStyle(.red).textSelection(.enabled)
                    if state.missingKey { Button("Open Settings", action: settings) }
                }
            }
            if state.error != nil, let captureArea {
                Button("Capture an area…", action: captureArea)
            }
            HStack {
                Button(state.copied ? "Copied ✓" : "Copy", action: copy)
                if let chat { Button("Chat about this", action: chat) }
                Spacer()
                Button("Close", action: close)
            }
        }
        .padding(12)
        .frame(minWidth: 280, minHeight: 160)
        .background(.regularMaterial)
    }
}
