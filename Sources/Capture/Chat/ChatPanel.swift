import AppKit
import SwiftUI

@MainActor
private final class ChatInput: ObservableObject {
    @Published var text = ""
    @Published var focused = false
}

@MainActor
final class ChatPanel: NSObject, NSWindowDelegate {
    private let session: ChatSession
    private let input = ChatInput()
    private var panel: FloatingPanel?
    private var keyMonitor: Any?

    init(capture: CaptureResult, seed: String?) {
        session = ChatSession(capture: capture, seed: seed, settings: .shared)
    }

    var window: NSWindow? { panel }
    var frame: CGRect? { panel?.isVisible == true ? panel?.frame : nil }
    var isKey: Bool { panel?.isKeyWindow == true }
    var preventsOutsideDismissal: Bool { session.preventsOutsideDismissal }
    func stop() { session.stop() }

    func show(avoiding: CGRect? = nil) {
        if panel == nil {
            guard
                let screen = NSScreen.screens.first(where: { $0.captureDisplayID == session.capture.displayID })
                    ?? FloatingPanel.screen(containing: session.capture.rect)
            else { return }
            let view = ChatPanelView(session: session, input: input, send: { [weak self] in self?.sendInput() })
            let frame = FloatingPanel.frameBeside(
                selection: session.capture.rect, visibleFrame: screen.visibleFrame,
                size: CGSize(width: 380, height: 520),
                minimumSize: CGSize(width: 320, height: 360), avoiding: avoiding)
            let window = FloatingPanel(frame: frame, titled: true, content: view)
            window.styleMask.insert(.resizable)
            window.minSize = NSSize(width: 320, height: 360)
            window.title = "Capture Chat"
            window.delegate = self
            panel = window
            keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self, weak window] event in
                guard let self, let window, window.isKeyWindow, self.input.focused,
                    event.keyCode == 36 || event.keyCode == 76
                else { return event }
                let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
                guard flags.isDisjoint(with: [.command, .control]) else { return event }
                if !flags.isDisjoint(with: [.shift, .option]), let editor = window.firstResponder as? NSTextView {
                    editor.insertText("\n", replacementRange: editor.selectedRange())
                } else if flags.isDisjoint(with: [.shift, .option]) {
                    self.sendInput()
                } else {
                    return event
                }
                return nil
            }
        }
        NSApp.activate(ignoringOtherApps: true)
        panel?.makeKeyAndOrderFront(nil)
        input.focused = true
    }

    func send(_ text: String) { session.send(text) }

    func close() {
        session.stop()
        panel?.close()
        panel = nil
        removeMonitor()
    }

    func windowWillClose(_ notification: Notification) {
        session.stop()
        panel = nil
        removeMonitor()
    }

    private func removeMonitor() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
    }

    private func sendInput() {
        let text = input.text
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !session.isBusy else { return }
        input.text = ""
        session.send(text)
    }
}

@MainActor
private struct ChatPanelView: View {
    @ObservedObject var session: ChatSession
    @ObservedObject var input: ChatInput
    let send: () -> Void
    @State private var expanded = false
    @FocusState private var inputFocused: Bool

    var body: some View {
        VStack(spacing: 8) {
            Button {
                expanded.toggle()
            } label: {
                Image(nsImage: NSImage(cgImage: session.capture.image, size: .zero))
                    .resizable().scaledToFit()
                    .frame(maxWidth: expanded ? 350 : 110, maxHeight: expanded ? 230 : 65)
                    .clipShape(RoundedRectangle(cornerRadius: 5))
            }
            .buttonStyle(.plain)
            .help(expanded ? "Shrink preview" : "Expand preview")
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(session.messages) { message in
                            messageRow(message)
                        }
                        if let pending = session.pendingAction {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(pending.description)
                                HStack {
                                    Button("Allow") { session.decide(.allow) }
                                    Button("Allow all") { session.decide(.allowAll) }
                                    Button("Deny") { session.decide(.deny) }
                                }
                            }.padding(8).background(Color.accentColor.opacity(0.12)).clipShape(
                                RoundedRectangle(cornerRadius: 8))
                        }
                        Color.clear.frame(height: 1).id("bottom")
                    }.frame(maxWidth: .infinity)
                }
                .onChange(of: session.pendingAction?.id) { _, _ in proxy.scrollTo("bottom", anchor: .bottom) }
                .onChange(of: session.messages.count) { _, _ in proxy.scrollTo("bottom", anchor: .bottom) }
                .onChange(of: session.messages.last?.text) { _, _ in proxy.scrollTo("bottom", anchor: .bottom) }
            }
            HStack(alignment: .bottom, spacing: 8) {
                TextField("Ask about this selection…", text: $input.text, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...5)
                    .focused($inputFocused)
                    .onSubmit(send)
                if session.isBusy {
                    Button("Stop") { session.stop() }
                } else {
                    Button("Send", action: send)
                        .disabled(input.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            HStack {
                Button {
                    session.recapture()
                } label: {
                    Label("Recapture", systemImage: "camera.viewfinder")
                }
                .disabled(session.isBusy)
                Spacer()
                Button("New chat") {
                    session.reset()
                    input.text = ""
                    inputFocused = true
                }
            }
        }
        .padding(12)
        .frame(minWidth: 320, minHeight: 360)
        .background(.regularMaterial)
        .onAppear { inputFocused = true }
        .onChange(of: inputFocused) { _, value in input.focused = value }
        .onChange(of: input.focused) { _, value in inputFocused = value }
    }

    @ViewBuilder
    private func messageRow(_ message: ChatSession.Message) -> some View {
        if message.activity {
            Text(message.text).font(.caption).foregroundStyle(.secondary).frame(
                maxWidth: .infinity, alignment: .leading)
        } else {
            HStack(alignment: .top) {
                if message.role == .user { Spacer(minLength: 35) }
                VStack(alignment: .leading, spacing: 5) {
                    if let thumbnail = message.thumbnail {
                        Image(nsImage: thumbnail).resizable().scaledToFit().frame(maxWidth: 140, maxHeight: 90)
                    }
                    if !message.text.isEmpty {
                        Text(markdown(message.text)).textSelection(.enabled)
                    }
                    if message.accessibilityNotice {
                        Button("Open Accessibility Settings") {
                            if let url = URL(
                                string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
                            {
                                NSWorkspace.shared.open(url)
                            }
                        }
                    }
                    if message.isStreaming && message.text.isEmpty { ProgressView().controlSize(.small) }
                    if let error = message.error {
                        Text(error).foregroundStyle(.red).textSelection(.enabled)
                        Button("Retry") { session.retry() }.disabled(session.isBusy)
                    } else if message.role == .assistant && !message.isStreaming && !message.text.isEmpty {
                        Button {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(message.text, forType: .string)
                        } label: {
                            Label("Copy", systemImage: "doc.on.doc")
                        }
                        .buttonStyle(.plain).font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(8)
                .background(message.role == .user ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                if message.role != .user { Spacer(minLength: 35) }
            }
        }
    }

    private func markdown(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(text)
    }
}
