import AppKit
import os

@MainActor
final class CaptureCoordinator {
    private let logger = Logger(subsystem: "com.sozay.capture", category: "Capture")
    private let capturer = ScreenCapturer()
    private let overlay = SelectionOverlayController()
    private var isCapturing = false
    private(set) var current: CaptureResult?
    var openSettings: () -> Void = {}
    private lazy var sessionUI = CaptureSessionUI(
        extractText: { [weak self] in self?.extractText() },
        translate: { [weak self] in self?.translate() },
        openChat: { [weak self] in self?.openChat() },
        openSettings: { [weak self] in self?.openSettings() }
    )

    func startCapture() {
        startCapture(debugRect: nil, debugAction: nil)
    }

    #if DEBUG
    func startDebugCapture(rect: CGRect, action: String?) {
        startCapture(debugRect: rect, debugAction: action)
    }
    #endif

    private func startCapture(debugRect: CGRect?, debugAction: String?) {
        guard !isCapturing else { return }
        // Remove our floating windows before requesting the next freeze frame.
        sessionUI.dismiss()
        current = nil
        isCapturing = true
        guard capturer.hasPermission else {
            capturer.requestPermission()
            isCapturing = false
            return
        }
        Task {
            defer { isCapturing = false }
            do {
                let frozen = try await capturer.captureAllDisplays()
                let rect: CGRect
                let displayID: CGDirectDisplayID
                if let debugRect {
                    displayID = CGMainDisplayID()
                    guard let display = frozen[displayID], !debugRect.isEmpty,
                          !debugRect.isInfinite, !debugRect.isNull, display.frame.contains(debugRect) else {
                        throw ScreenCapturer.CaptureError.invalidRegion
                    }
                    rect = debugRect
                } else {
                    guard let selection = await overlay.run(frozen: frozen) else { return }
                    rect = selection.rect
                    displayID = selection.displayID
                }
                guard let display = frozen[displayID] else {
                    throw ScreenCapturer.CaptureError.displayUnavailable
                }
                let scale = CGFloat(display.image.width) / display.frame.width
                let local = rect.offsetBy(dx: -display.frame.minX, dy: -display.frame.minY)
                let pixelRect = CGRect(x: local.minX * scale, y: local.minY * scale,
                                       width: local.width * scale, height: local.height * scale)
                guard let image = display.image.cropping(to: pixelRect) else {
                    throw ScreenCapturer.CaptureError.cropFailed
                }
                let result = CaptureResult(image: image, rect: rect,
                                           displayID: displayID, scale: scale)
                current = result
                logger.info("Captured rect \(NSStringFromRect(result.rect), privacy: .public), pixels \(image.width) × \(image.height)")
                sessionUI.show(for: result)
                #if DEBUG
                switch debugAction {
                case "ocr": extractText()
                case "translate": translate()
                case "chat":
                    openChat()
                    if let message = UserDefaults.standard.string(forKey: "debugChatMessage") {
                        sessionUI.sendDebugChatMessage(message)
                    }
                default: break
                }
                #endif
            } catch {
                logger.error("Capture failed: \(error.localizedDescription, privacy: .public)")
                let alert = NSAlert()
                alert.messageText = "Capture Failed"
                alert.informativeText = error.localizedDescription
                NSApp.activate(ignoringOtherApps: true)
                alert.runModal()
            }
        }
    }

    func extractText() {
        guard let current else { return }
        let settings = AppSettings.shared
        let model = settings.ocrEngine == .onDevice ? "On-device" : settings.visionModel
        sessionUI.showResult(for: current, title: "Text", model: model,
                             stream: TextExtractor(settings: settings).extract(from: current),
                             openChat: { [weak self] in self?.openChat(seed: $0) })
    }

    func translate() {
        guard let current else { return }
        let settings = AppSettings.shared
        if settings.translationDisplay == .overlay {
            sessionUI.showTranslationOverlay(for: current, openChat: { [weak self] in self?.openChat(seed: $0) })
            return
        }
        sessionUI.dismissTranslationOverlay()
        sessionUI.showResult(for: current, title: "Translation → \(settings.targetLanguage)",
                             model: settings.visionModel,
                             stream: Translator(settings: settings).translate(from: current),
                             openChat: { [weak self] in self?.openChat(seed: $0) })
    }

    func openChat(seed: String? = nil) {
        guard let current else { return }
        sessionUI.showChat(for: current, seed: seed)
    }
}
