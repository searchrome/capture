import AppKit
import Combine
import CoreGraphics

@MainActor
final class ChatSession: ObservableObject {
    struct Message: Identifiable {
        let id = UUID()
        let role: ChatMessage.Role
        var text: String
        var thumbnail: NSImage? = nil
        var isStreaming = false
        var error: String? = nil
        var activity = false
        var accessibilityNotice = false
    }
    struct PendingAction: Identifiable {
        let id = UUID()
        let description: String
    }
    enum Decision { case allow, allowAll, deny }

    let capture: CaptureResult
    @Published private(set) var messages: [Message] = []
    @Published private(set) var isBusy = false
    @Published private(set) var pendingAction: PendingAction?
    private(set) var history: [ChatMessage] = []
    private(set) var currentTask: Task<Void, Never>?
    private let settings: AppSettings
    private let client: OpenRouterClient
    private let seed: String?
    private let marker = TargetMarker()
    private let synthesizer = InputSynthesizer()
    private var initialImage: ChatContentPart?
    private var sentImageSize = CGSize.zero
    private var targetApp: NSRunningApplication?
    private var pendingDecision: CheckedContinuation<Decision, Never>?
    private var outstandingCalls: [String] = []
    private var operationID = UUID()
    private enum Retry { case response, recapture }
    private var retryOperation: Retry?

    init(capture: CaptureResult, seed: String?, settings: AppSettings, client: OpenRouterClient = OpenRouterClient()) {
        self.capture = capture
        self.seed = seed?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.settings = settings
        self.client = client
        targetApp = Self.app(at: CGPoint(x: capture.rect.midX, y: capture.rect.midY))
        reset()
    }
    func reset() {
        stop()
        messages = []
        retryOperation = nil
        let image = capture.llmImage(maxSide: max(1, settings.maxImageSide))
        sentImageSize = image.size
        initialImage = .imageURL("data:image/png;base64,\(image.png.base64EncodedString())")
        history = [ChatMessage(role: .system, content: .text(systemPrompt(imageSize: image.size)))]
    }
    func send(_ text: String) {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isBusy else { return }
        clearError()
        var parts: [ChatContentPart] = []
        if let image = initialImage {
            parts.append(.text("Screenshot size: \(Int(sentImageSize.width))×\(Int(sentImageSize.height)) px."))
            parts.append(image)
            initialImage = nil
            if let seed, !seed.isEmpty { parts.append(.text("Text extracted from the selection: \(seed)")) }
        }
        parts.append(.text(text))
        history.append(ChatMessage(role: .user, content: .parts(parts)))
        trimImages()
        messages.append(Message(role: .user, text: text))
        startResponse()
    }
    func decide(_ decision: Decision) {
        pendingAction = nil
        marker.hide()
        let continuation = pendingDecision
        pendingDecision = nil
        continuation?.resume(returning: decision)
    }
    func stop() {
        operationID = UUID()
        currentTask?.cancel()
        currentTask = nil
        decide(.deny)
        marker.hide()
        for id in outstandingCalls {
            history.append(ChatMessage(role: .tool, content: .text("Action cancelled by user."), toolCallID: id))
        }
        outstandingCalls = []
        if let index = messages.lastIndex(where: { $0.isStreaming }) {
            messages[index].isStreaming = false
            let text = messages[index].text
            if !text.isEmpty {
                history.append(ChatMessage(role: .assistant, content: .text(text)))
            } else {
                messages.remove(at: index)
            }
        }
        isBusy = false
    }
    func retry() {
        guard !isBusy, let operation = retryOperation else { return }
        clearError()
        switch operation {
        case .response: startResponse()
        case .recapture: recapture()
        }
    }
    func recapture() {
        guard !isBusy else { return }
        clearError()
        isBusy = true
        let id = UUID()
        operationID = id
        currentTask = Task { [weak self] in
            guard let self else { return }
            do {
                let updated = try await captureImage()
                try Task.checkCancellation()
                guard operationID == id else { return }
                if let image = initialImage {
                    var parts: [ChatContentPart] = [
                        .text("Screenshot size: \(Int(sentImageSize.width))×\(Int(sentImageSize.height)) px."), image,
                    ]
                    if let seed, !seed.isEmpty { parts.append(.text("Text extracted from the selection: \(seed)")) }
                    history.append(ChatMessage(role: .user, content: .parts(parts)))
                    initialImage = nil
                }
                appendScreenshot(
                    updated, prefix: "Here is an updated screenshot of the same area.", showThumbnail: true)
                isBusy = false
                currentTask = nil
            } catch {
                guard operationID == id, !Task.isCancelled else { return }
                isBusy = false
                currentTask = nil
                retryOperation = .recapture
                messages.append(Message(role: .assistant, text: "", error: error.localizedDescription))
            }
        }
    }
    private struct ResponseState {
        var steps = 0
        var allowAll = false
        var lastTargetPoint: CGPoint?
    }

    private func startResponse() {
        isBusy = true
        let id = UUID()
        operationID = id
        currentTask = Task { [weak self] in
            guard let self else { return }
            var state = ResponseState()
            do {
                while true {
                    guard let calls = try await streamTurn(operation: id) else { return }
                    if calls.isEmpty { break }
                    let screenshot = try await runToolCalls(calls, state: &state)
                    try Task.checkCancellation()
                    guard operationID == id else { return }
                    if let screenshot {
                        appendScreenshot(
                            screenshot, prefix: "Updated screenshot after your actions.", showThumbnail: false)
                    }
                    if state.steps >= 25 {
                        messages.append(
                            Message(
                                role: .assistant, text: "Stopped after 25 tool steps. Send another message to continue."
                            )
                        )
                        break
                    }
                }
                guard operationID == id else { return }
                isBusy = false
                currentTask = nil
                #if DEBUG
                snapshotTranscript()
                #endif
            } catch {
                guard operationID == id, !Task.isCancelled else { return }
                handleResponseError(error)
                #if DEBUG
                snapshotTranscript()
                #endif
            }
        }
    }

    #if DEBUG
    private func snapshotTranscript() {
        let transcript = messages.map { message in
            let content = [message.text, message.error].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: "\n")
            return "\(message.role.rawValue): \(content)"
        }.joined(separator: "\n\n")
        DebugSnapshots.writeText(transcript + "\n\n", file: "chat.txt", append: true)
        DispatchQueue.main.async { DebugSnapshots.write(name: "chat") }
    }
    #endif

    private func streamTurn(operation id: UUID) async throws -> [ChatToolCall]? {
        try Task.checkCancellation()
        guard operationID == id else { return nil }
        let message = Message(role: .assistant, text: "", isStreaming: true)
        messages.append(message)
        var calls: [Int: ToolCallDelta] = [:]
        let request = ChatRequest(model: settings.chatModel, messages: history, tools: AgentTools.definitions)
        for try await event in client.stream(request) {
            try Task.checkCancellation()
            guard operationID == id else { return nil }
            switch event {
            case .text(let text):
                if let index = messages.firstIndex(where: { $0.id == message.id }) {
                    messages[index].text += text
                }
            case .toolCall(let delta):
                calls[delta.index] = delta
            default:
                break
            }
        }
        try Task.checkCancellation()
        guard operationID == id, let index = messages.firstIndex(where: { $0.id == message.id }) else { return nil }
        let text = messages[index].text
        messages[index].isStreaming = false
        let toolCalls = calls.keys.sorted().compactMap { calls[$0] }.map {
            ChatToolCall(id: $0.id, function: .init(name: $0.name, arguments: $0.arguments))
        }
        if toolCalls.isEmpty {
            history.append(ChatMessage(role: .assistant, content: .text(text)))
            return []
        }
        if text.isEmpty { messages.remove(at: index) }
        history.append(ChatMessage(role: .assistant, content: text.isEmpty ? nil : .text(text), toolCalls: toolCalls))
        outstandingCalls = toolCalls.map(\.id)
        return toolCalls
    }

    private func runToolCalls(_ calls: [ChatToolCall], state: inout ResponseState) async throws -> CaptureResult? {
        var lastScreenshot: CaptureResult?
        var lastWasScreenshot = false
        for call in calls {
            try Task.checkCancellation()
            if state.steps >= 25 {
                appendToolResult(call, "Tool step limit reached.")
                continue
            }
            state.steps += 1
            lastWasScreenshot = false
            do {
                let action = try AgentTools.parse(call)
                let point = try screenPoint(for: action)
                let description = action.description(app: targetApp?.localizedName)
                let previewPoint = point ?? state.lastTargetPoint
                if settings.askBeforeActing && !state.allowAll {
                    if let previewPoint { marker.show(at: previewPoint) }
                    let decision = await withCheckedContinuation { continuation in
                        self.pendingDecision = continuation
                        self.pendingAction = PendingAction(description: description)
                    }
                    try Task.checkCancellation()
                    if case .deny = decision {
                        appendToolResult(call, "User denied this action.")
                        continue
                    }
                    if case .allowAll = decision { state.allowAll = true }
                }
                if case .takeScreenshot = action {
                    lastScreenshot = try await captureImage()
                    try Task.checkCancellation()
                    lastWasScreenshot = true
                } else {
                    if let previewPoint { marker.show(at: previewPoint) }
                    try await synthesizer.perform(action, point: point, targetApp: targetApp)
                    if let point { state.lastTargetPoint = point }
                }
                messages.append(Message(role: .tool, text: description, activity: true))
                appendToolResult(call, "Action completed.")
                if previewPoint != nil {
                    try await Task.sleep(nanoseconds: 400_000_000)
                    marker.hide()
                }
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                marker.hide()
                appendToolResult(call, error.localizedDescription)
                if error.localizedDescription == InputSynthesizer.accessibilityMessage {
                    messages.append(
                        Message(role: .assistant, text: error.localizedDescription, accessibilityNotice: true))
                }
            }
        }
        if !lastWasScreenshot {
            try await Task.sleep(nanoseconds: 500_000_000)
            lastScreenshot = try await captureImage()
        }
        return lastScreenshot
    }

    private func screenPoint(for action: AgentAction) throws -> CGPoint? {
        guard let pixel = action.pixel else { return nil }
        guard pixel.x >= 0, pixel.y >= 0, pixel.x < sentImageSize.width, pixel.y < sentImageSize.height else {
            let size = "\(Int(sentImageSize.width))×\(Int(sentImageSize.height))"
            throw InputSynthesizer.ActionError(
                message: "Coordinates must be inside the latest screenshot (\(size) px).")
        }
        return capture.screenPoint(for: pixel, sentImageSize: sentImageSize)
    }

    private func handleResponseError(_ error: Error) {
        marker.hide()
        for callID in outstandingCalls {
            history.append(ChatMessage(role: .tool, content: .text("Action interrupted."), toolCallID: callID))
        }
        outstandingCalls = []
        if let index = messages.lastIndex(where: { $0.isStreaming }) {
            messages[index].isStreaming = false
            messages[index].error = error.localizedDescription
        } else {
            messages.append(Message(role: .assistant, text: "", error: error.localizedDescription))
        }
        retryOperation = .response
        isBusy = false
        currentTask = nil
    }
    private func appendToolResult(_ call: ChatToolCall, _ result: String) {
        history.append(ChatMessage(role: .tool, content: .text(result), toolCallID: call.id))
        if let index = outstandingCalls.firstIndex(of: call.id) { outstandingCalls.remove(at: index) }
    }
    private func captureImage() async throws -> CaptureResult {
        try await ScreenCapturer().capture(rect: capture.rect, displayID: capture.displayID)
    }
    private func appendScreenshot(_ updated: CaptureResult, prefix: String, showThumbnail: Bool) {
        let encoded = updated.llmImage(maxSide: max(1, settings.maxImageSide))
        sentImageSize = encoded.size
        let text = "\(prefix) Size \(Int(encoded.size.width))×\(Int(encoded.size.height)) px."
        history.append(
            ChatMessage(
                role: .user,
                content: .parts([.text(text), .imageURL("data:image/png;base64,\(encoded.png.base64EncodedString())")]))
        )
        trimImages()
        if showThumbnail {
            messages.append(Message(role: .user, text: text, thumbnail: NSImage(cgImage: updated.image, size: .zero)))
        }
    }
    private func clearError() {
        messages.removeAll { $0.error != nil }
        retryOperation = nil
    }
    private func trimImages() {
        var remaining = 2
        for index in history.indices.reversed() {
            guard case .parts(let parts) = history[index].content else { continue }
            var updated = parts
            for partIndex in parts.indices.reversed() where parts[partIndex].type == "image_url" {
                if remaining > 0 { remaining -= 1 } else { updated[partIndex] = .text("[earlier screenshot omitted]") }
            }
            history[index].content = .parts(updated)
        }
    }
    private func systemPrompt(imageSize: CGSize) -> String {
        let bounds = CGDisplayBounds(capture.displayID)
        let rect = capture.rect
        let context =
            "Selection rect in global screen points: x=\(rect.minX), y=\(rect.minY), "
            + "width=\(rect.width), height=\(rect.height). Screen size: \(bounds.width) × \(bounds.height) points. "
            + "Sent image size: \(Int(imageSize.width)) × \(Int(imageSize.height)) pixels. "
            + "App under selection: \(targetApp?.localizedName ?? "unknown")."
        return "You are an assistant built into a macOS screen-capture tool. "
            + "The user selected an area of their screen; its image is attached. "
            + "Answer questions about its content, be concise, and reply in the user's language. "
            + "You can operate on the selected area using tools to help fill forms. Act only inside the selection. "
            + "Briefly explain what you will do. Ask for any personal data you do not know instead of guessing. "
            + "Never submit or send a form or enter passwords or payment details unless the user explicitly asked "
            + "in this chat. \(context)"
    }
    private static func app(at point: CGPoint) -> NSRunningApplication? {
        guard
            let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]]
        else { return nil }
        let ownPID = ProcessInfo.processInfo.processIdentifier
        for window in windows {
            guard let layer = (window[kCGWindowLayer as String] as? NSNumber)?.intValue, layer == 0,
                let alpha = (window[kCGWindowAlpha as String] as? NSNumber)?.doubleValue, alpha > 0,
                let pid = (window[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value, pid != ownPID,
                let bounds = window[kCGWindowBounds as String] as? [String: Any],
                let rect = CGRect(dictionaryRepresentation: bounds as CFDictionary), rect.contains(point)
            else { continue }
            if let app = NSRunningApplication(processIdentifier: pid) { return app }
        }
        return nil
    }
}
