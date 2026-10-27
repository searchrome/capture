import AppKit
import SwiftUI

@MainActor
final class TargetMarker {
    private var window: NSWindow?
    func show(at point: CGPoint) {
        hide()
        let size: CGFloat = 32
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        let frame = CGRect(x: point.x - size / 2, y: primaryHeight - point.y - size / 2, width: size, height: size)
        let panel = NSPanel(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
        panel.identifier = NSUserInterfaceItemIdentifier("capture.targetMarker")
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.level = .screenSaver
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = NSHostingView(rootView: MarkerView())
        panel.orderFrontRegardless()
        window = panel
    }
    func hide() {
        window?.orderOut(nil)
        window?.close()
        window = nil
    }
}

private struct MarkerView: View {
    var body: some View {
        ZStack {
            Circle().stroke(Color.red, lineWidth: 3).frame(width: 28, height: 28)
            Circle().fill(Color.red).frame(width: 5, height: 5)
        }.frame(width: 32, height: 32)
    }
}
