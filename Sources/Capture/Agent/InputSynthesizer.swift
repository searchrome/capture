import AppKit
import ApplicationServices

@MainActor
final class InputSynthesizer {
    static let syntheticEventMarker: Int64 = 0x43617074757265
    static let accessibilityMessage =
        "Accessibility access is required to perform this action. Grant access in System Settings and try again."

    func perform(_ action: AgentAction, point: CGPoint?, targetApp: NSRunningApplication?) async throws {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        guard AXIsProcessTrustedWithOptions(options) else { throw ActionError(message: Self.accessibilityMessage) }
        try Task.checkCancellation()
        var hidden: [NSWindow] = []
        if let point {
            let appPoint = CGPoint(x: point.x, y: (NSScreen.screens.first?.frame.height ?? 0) - point.y)
            hidden = NSApp.windows.filter {
                $0.isVisible && $0.identifier?.rawValue != "capture.targetMarker" && $0.frame.contains(appPoint)
            }
            hidden.forEach { $0.orderOut(nil) }
        }
        defer { hidden.reversed().forEach { $0.orderFrontRegardless() } }
        if let targetApp {
            targetApp.activate()
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        switch action {
        case .click(_, _, let button, let count):
            guard let point else { throw ActionError(message: "Missing target point.") }
            let mouse: CGMouseButton = button == "right" ? .right : .left
            let down: CGEventType = mouse == .right ? .rightMouseDown : .leftMouseDown
            let up: CGEventType = mouse == .right ? .rightMouseUp : .leftMouseUp
            CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: point, mouseButton: mouse)?
                .post(tap: .cghidEventTap)
            var postedClick = false
            do {
                for index in 1...count {
                    try Task.checkCancellation()
                    for type in [down, up] {
                        guard
                            let event = CGEvent(
                                mouseEventSource: nil, mouseType: type, mouseCursorPosition: point, mouseButton: mouse
                            )
                        else { throw ActionError(message: "Could not create mouse event.") }
                        event.setIntegerValueField(.mouseEventClickState, value: Int64(index))
                        event.setIntegerValueField(.eventSourceUserData, value: Self.syntheticEventMarker)
                        event.post(tap: .cghidEventTap)
                        postedClick = true
                    }
                }
            } catch {
                if postedClick { await waitForPostedEvents() }
                throw error
            }
            if postedClick { await waitForPostedEvents() }
        case .typeText(let text):
            var chunk: [UniChar] = []
            func sendChunk() throws {
                guard !chunk.isEmpty else { return }
                for down in [true, false] {
                    guard let event = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: down) else {
                        throw ActionError(message: "Could not create keyboard event.")
                    }
                    chunk.withUnsafeBufferPointer {
                        event.keyboardSetUnicodeString(stringLength: chunk.count, unicodeString: $0.baseAddress)
                    }
                    event.post(tap: .cghidEventTap)
                }
            }
            for scalar in text.unicodeScalars {
                let units = Array(String(scalar).utf16)
                if chunk.count + units.count > 20 {
                    try Task.checkCancellation()
                    try sendChunk()
                    chunk.removeAll()
                    try await Task.sleep(nanoseconds: 20_000_000)
                }
                chunk.append(contentsOf: units)
            }
            try Task.checkCancellation()
            try sendChunk()
        case .pressKey(let key, let modifiers):
            let codes: [String: CGKeyCode] = [
                "return": 36, "tab": 48, "escape": 53, "delete": 51, "space": 49, "up": 126, "down": 125, "left": 123,
                "right": 124, "home": 115, "end": 119, "pageup": 116, "pagedown": 121,
            ]
            guard let code = codes[key] else { throw ActionError(message: "Unsupported key.") }
            var flags: CGEventFlags = []
            for modifier in modifiers {
                switch modifier {
                case "cmd": flags.insert(.maskCommand)
                case "shift": flags.insert(.maskShift)
                case "option": flags.insert(.maskAlternate)
                case "control": flags.insert(.maskControl)
                default: break
                }
            }
            for down in [true, false] {
                guard let event = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: down) else {
                    throw ActionError(message: "Could not create keyboard event.")
                }
                event.flags = flags
                event.post(tap: .cghidEventTap)
            }
        case .scroll(_, _, let dy):
            guard let point,
                let event = CGEvent(
                    scrollWheelEvent2Source: nil, units: .line, wheelCount: 1, wheel1: -Int32(dy), wheel2: 0, wheel3: 0)
            else { throw ActionError(message: "Could not create scroll event.") }
            event.location = point
            event.post(tap: .cghidEventTap)
            await waitForPostedEvents()
        case .takeScreenshot: break
        }
    }
    // Once posted, events need time to reach their target even if the task is cancelled.
    private func waitForPostedEvents() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                continuation.resume()
            }
        }
    }

    struct ActionError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }
}
