import AppKit

@MainActor
final class SelectionOverlayController {
    private var windows: [SelectionOverlayWindow] = []
    private var continuation: CheckedContinuation<(rect: CGRect, displayID: CGDirectDisplayID)?, Never>?

    func run(frozen: [CGDirectDisplayID: (image: CGImage, frame: CGRect)]) async
        -> (rect: CGRect, displayID: CGDirectDisplayID)? {
        guard continuation == nil, let primary = NSScreen.screens.first else { return nil }
        let primaryHeight = primary.frame.height
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
            for screen in NSScreen.screens {
                guard let displayID = screen.captureDisplayID, let capture = frozen[displayID] else { continue }
                let window = SelectionOverlayWindow(screen: screen, image: capture.image) { [weak self] rect in
                    guard let rect else { self?.finish(nil); return }
                    // The view is flipped (top-left); the window's frame is still in AppKit space.
                    let globalRect = Self.globalRect(for: rect, screenFrame: screen.frame,
                                                     primaryHeight: primaryHeight)
                    self?.finish((globalRect, displayID))
                }
                windows.append(window)
            }
            guard !windows.isEmpty else { finish(nil); return }
            NSApp.activate(ignoringOtherApps: true)
            for window in windows { window.orderFrontRegardless() }
            let active = windows.first { $0.frame.contains(NSEvent.mouseLocation) } ?? windows[0]
            active.makeKeyAndOrderFront(nil)
            active.makeFirstResponder(active.contentView)
            NSCursor.crosshair.set()
            #if DEBUG
            NSLog("selection overlay shown on %d screens", windows.count)
            #endif
        }
    }

    static func globalRect(for localRect: CGRect, screenFrame: CGRect, primaryHeight: CGFloat) -> CGRect {
        CGRect(x: screenFrame.minX + localRect.minX,
               y: primaryHeight - screenFrame.maxY + localRect.minY,
               width: localRect.width, height: localRect.height)
    }

    private func finish(_ result: (rect: CGRect, displayID: CGDirectDisplayID)?) {
        let pending = continuation
        continuation = nil
        for window in windows { window.orderOut(nil); window.close() }
        windows.removeAll()
        pending?.resume(returning: result)
    }
}

@MainActor
private final class SelectionOverlayWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    private let complete: (CGRect?) -> Void

    init(screen: NSScreen, image: CGImage, complete: @escaping (CGRect?) -> Void) {
        self.complete = complete
        // The `screen:` variant calls init(contentRect:styleMask:backing:defer:), which this subclass
        // does not inherit, so it traps at runtime. setFrame places the window on `screen` instead.
        super.init(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        setFrame(screen.frame, display: false)
        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isOpaque = true
        backgroundColor = .black
        hasShadow = false
        acceptsMouseMovedEvents = true
        isReleasedWhenClosed = false
        contentView = SelectionOverlayView(image: image, complete: complete)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { complete(nil) } else { super.keyDown(with: event) }
    }

    override func cancelOperation(_ sender: Any?) { complete(nil) }
}

@MainActor
private final class SelectionOverlayView: NSView {
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    private let image: NSImage
    private let complete: (CGRect?) -> Void
    private var start: CGPoint?
    private var cursor = CGPoint.zero
    private var selection: CGRect?
    private var trackingArea: NSTrackingArea?

    init(image: CGImage, complete: @escaping (CGRect?) -> Void) {
        self.image = NSImage(cgImage: image, size: CGSize(width: image.width, height: image.height))
        self.complete = complete
        super.init(frame: .zero)
        autoresizingMask = [.width, .height]
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(rect: .zero,
                                  options: [.activeAlways, .inVisibleRect, .cursorUpdate,
                                            .mouseEnteredAndExited, .mouseMoved],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        trackingArea = area
        super.updateTrackingAreas()
    }

    override func cursorUpdate(with event: NSEvent) { NSCursor.crosshair.set() }

    override func mouseEntered(with event: NSEvent) {
        focusOverlay()
        NSCursor.crosshair.set()
    }

    override func mouseMoved(with event: NSEvent) { NSCursor.crosshair.set() }

    private func focusOverlay() {
        window?.makeKey()
        window?.makeFirstResponder(self)
    }

    override func draw(_ dirtyRect: NSRect) {
        image.draw(in: bounds, from: .zero, operation: .copy, fraction: 1, respectFlipped: true, hints: nil)
        let dim = NSBezierPath(rect: bounds)
        if let selection { dim.appendRect(selection) }
        dim.windingRule = .evenOdd
        NSColor.black.withAlphaComponent(0.35).setFill()
        dim.fill()
        guard let selection else { return }
        NSColor.white.setStroke()
        let border = NSBezierPath(rect: selection)
        border.lineWidth = 1
        border.stroke()
        drawLabel(for: selection)
    }

    private func drawLabel(for rect: CGRect) {
        let text = "\(Int(rect.width.rounded())) × \(Int(rect.height.rounded()))" as NSString
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium),
            .foregroundColor: NSColor.white
        ]
        let size = text.size(withAttributes: attributes)
        let labelSize = CGSize(width: size.width + 16, height: size.height + 10)
        let origin = CGPoint(
            x: max(0, min(cursor.x + 14, bounds.width - labelSize.width)),
            y: max(0, min(cursor.y + 18, bounds.height - labelSize.height))
        )
        let label = CGRect(origin: origin, size: labelSize)
        NSColor.black.withAlphaComponent(0.8).setFill()
        NSBezierPath(roundedRect: label, xRadius: 5, yRadius: 5).fill()
        text.draw(at: CGPoint(x: label.minX + 8, y: label.minY + 5), withAttributes: attributes)
    }

    private func confinedPoint(_ event: NSEvent) -> CGPoint {
        let point = convert(event.locationInWindow, from: nil)
        return CGPoint(x: min(max(point.x, 0), bounds.width), y: min(max(point.y, 0), bounds.height))
    }

    override func mouseDown(with event: NSEvent) {
        focusOverlay()
        start = confinedPoint(event)
        updateSelection(event)
    }

    override func mouseDragged(with event: NSEvent) { updateSelection(event) }

    private func updateSelection(_ event: NSEvent) {
        guard let start else { return }
        cursor = confinedPoint(event)
        selection = CGRect(x: min(start.x, cursor.x), y: min(start.y, cursor.y),
                           width: abs(cursor.x - start.x), height: abs(cursor.y - start.y))
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard start != nil else { return }
        updateSelection(event)
        guard let selection, selection.width >= 5, selection.height >= 5 else { complete(nil); return }
        complete(selection)
    }

    override func rightMouseDown(with event: NSEvent) { complete(nil) }
    override func cancelOperation(_ sender: Any?) { complete(nil) }
}
