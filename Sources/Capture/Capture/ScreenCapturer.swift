import AppKit
import ScreenCaptureKit

@MainActor
final class ScreenCapturer {
    enum CaptureError: LocalizedError {
        case displayUnavailable
        case invalidRegion
        case cropFailed

        var errorDescription: String? {
            switch self {
            case .displayUnavailable: return "The selected display is no longer available."
            case .invalidRegion: return "The selection is outside the selected display."
            case .cropFailed: return "The selected image could not be cropped."
            }
        }
    }

    var hasPermission: Bool { CGPreflightScreenCaptureAccess() }

    func requestPermission() {
        CGRequestScreenCaptureAccess()
        let alert = NSAlert()
        alert.messageText = "Allow Screen Recording"
        alert.informativeText = "Enable Capture in System Settings → Privacy & Security → Screen & System Audio Recording. You may need to restart Capture after granting access, then try capturing again."
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn,
           let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }

    func captureAllDisplays() async throws -> [CGDirectDisplayID: (image: CGImage, frame: CGRect)] {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        var frozen: [CGDirectDisplayID: (image: CGImage, frame: CGRect)] = [:]
        for display in content.displays {
            let configuration = configuration(for: display)
            let image = try await SCScreenshotManager.captureImage(
                contentFilter: filter(for: display, content: content), configuration: configuration
            )
            frozen[display.displayID] = (image, display.frame)
        }
        return frozen
    }

    func capture(rect: CGRect, displayID: CGDirectDisplayID) async throws -> CaptureResult {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first(where: { $0.displayID == displayID }) else {
            throw CaptureError.displayUnavailable
        }
        guard !rect.isEmpty, !rect.isInfinite, !rect.isNull, display.frame.contains(rect) else {
            throw CaptureError.invalidRegion
        }
        let scale = backingScale(for: display)
        let configuration = configuration(for: display)
        configuration.sourceRect = rect.offsetBy(dx: -display.frame.minX, dy: -display.frame.minY)
        configuration.width = max(1, Int((rect.width * scale).rounded()))
        configuration.height = max(1, Int((rect.height * scale).rounded()))
        let image = try await SCScreenshotManager.captureImage(
            contentFilter: filter(for: display, content: content), configuration: configuration
        )
        return CaptureResult(image: image, rect: rect, displayID: displayID, scale: scale)
    }

    private func filter(for display: SCDisplay, content: SCShareableContent) -> SCContentFilter {
        let ownApp = content.applications.filter { $0.processID == ProcessInfo.processInfo.processIdentifier }
        return SCContentFilter(display: display, excludingApplications: ownApp, exceptingWindows: [])
    }

    private func backingScale(for display: SCDisplay) -> CGFloat {
        NSScreen.screens.first { $0.captureDisplayID == display.displayID }?.backingScaleFactor
            ?? CGFloat(display.width) / display.frame.width
    }

    private func configuration(for display: SCDisplay) -> SCStreamConfiguration {
        let configuration = SCStreamConfiguration()
        let scale = backingScale(for: display)
        configuration.width = max(1, Int((display.frame.width * scale).rounded()))
        configuration.height = max(1, Int((display.frame.height * scale).rounded()))
        configuration.showsCursor = false
        return configuration
    }
}

extension NSScreen {
    var captureDisplayID: CGDirectDisplayID? {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }
}
