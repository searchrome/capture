import AppKit
import Carbon
import os

struct Hotkey: Codable, Equatable {
    var keyCode: UInt32
    var modifiers: UInt32

    static let `default` = Hotkey(keyCode: UInt32(kVK_ANSI_6), modifiers: UInt32(cmdKey | shiftKey))

    static let documentText = Hotkey(keyCode: UInt32(kVK_ANSI_7), modifiers: UInt32(cmdKey | optionKey))

    // Carbon virtual key codes describe physical keys, independent of modifier flags.
    var keyEquivalent: String {
        let keys: [UInt32: String] = [
            0: "a", 1: "s", 2: "d", 3: "f", 4: "h", 5: "g", 6: "z", 7: "x",
            8: "c", 9: "v", 11: "b", 12: "q", 13: "w", 14: "e", 15: "r",
            16: "y", 17: "t", 18: "1", 19: "2", 20: "3", 21: "4", 22: "6",
            23: "5", 24: "=", 25: "9", 26: "7", 27: "-", 28: "8", 29: "0",
            30: "]", 31: "o", 32: "u", 33: "[", 34: "i", 35: "p", 36: "\r",
            37: "l", 38: "j", 39: "'", 40: "k", 41: ";", 42: "\\", 43: ",",
            44: "/", 45: "n", 46: "m", 47: ".", 48: "\t", 49: " ", 50: "`",
            51: "\u{8}", 53: "\u{1b}", 123: "\u{f702}", 124: "\u{f703}",
            125: "\u{f701}", 126: "\u{f700}"
        ]
        return keys[keyCode] ?? ""
    }

    var modifierMask: NSEvent.ModifierFlags {
        var result: NSEvent.ModifierFlags = []
        if modifiers & UInt32(controlKey) != 0 { result.insert(.control) }
        if modifiers & UInt32(optionKey) != 0 { result.insert(.option) }
        if modifiers & UInt32(shiftKey) != 0 { result.insert(.shift) }
        if modifiers & UInt32(cmdKey) != 0 { result.insert(.command) }
        return result
    }

    var displayString: String {
        var result = ""
        if modifierMask.contains(.control) { result += "⌃" }
        if modifierMask.contains(.option) { result += "⌥" }
        if modifierMask.contains(.command) { result += "⌘" }
        if modifierMask.contains(.shift) { result += "⇧" }
        let labels: [String: String] = [
            "\r": "↩", "\t": "⇥", " ": "Space", "\u{8}": "⌫", "\u{1b}": "⎋",
            "\u{f702}": "←", "\u{f703}": "→", "\u{f701}": "↓", "\u{f700}": "↑"
        ]
        return result + (labels[keyEquivalent] ?? (keyEquivalent.isEmpty ? "Key \(keyCode)" : keyEquivalent.uppercased()))
    }
}

@MainActor
final class HotkeyManager {
    private static let signature: OSType = 0x43505452 // CPTR
    private let logger = Logger(subsystem: "com.sozay.capture", category: "Hotkey")
    private var hotkeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private var handler: (() -> Void)?
    private let id: UInt32

    init(id: UInt32 = 1) { self.id = id }

    @discardableResult
    func register(_ hotkey: Hotkey, handler: @escaping () -> Void) -> Bool {
        unregister()
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let installStatus = InstallEventHandler(GetApplicationEventTarget(), { _, event, userData in
            guard let event, let userData else { return OSStatus(eventNotHandledErr) }
            var hotkeyID = EventHotKeyID()
            let status = GetEventParameter(event, EventParamName(kEventParamDirectObject),
                                           EventParamType(typeEventHotKeyID), nil,
                                           MemoryLayout<EventHotKeyID>.size, nil, &hotkeyID)
            guard status == noErr, hotkeyID.signature == HotkeyManager.signature, hotkeyID.id == Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue().id else {
                return OSStatus(eventNotHandledErr)
            }
            // The application event target dispatches Carbon events on the main thread.
            MainActor.assumeIsolated {
                Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue().handler?()
            }
            return noErr
        }, 1, &eventType, Unmanaged.passUnretained(self).toOpaque(), &eventHandlerRef)
        guard installStatus == noErr else {
            logger.error("Hotkey event handler installation failed: \(installStatus)")
            return false
        }

        let hotkeyID = EventHotKeyID(signature: Self.signature, id: id)
        let status = RegisterEventHotKey(hotkey.keyCode, hotkey.modifiers, hotkeyID,
                                         GetApplicationEventTarget(), 0, &hotkeyRef)
        guard status == noErr else {
            logger.error("Hotkey registration failed: \(status)")
            unregister()
            return false
        }
        self.handler = handler
        return true
    }

    func unregister() {
        if let hotkeyRef { UnregisterEventHotKey(hotkeyRef) }
        if let eventHandlerRef { RemoveEventHandler(eventHandlerRef) }
        hotkeyRef = nil
        eventHandlerRef = nil
        handler = nil
    }

    deinit {
        if let hotkeyRef { UnregisterEventHotKey(hotkeyRef) }
        if let eventHandlerRef { RemoveEventHandler(eventHandlerRef) }
    }
}
