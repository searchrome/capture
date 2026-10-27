import AppKit
import SwiftUI

@MainActor
class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool { styleMask.contains(.titled) }
    init<Content: View>(frame: CGRect, titled: Bool = false, content: Content) {
        let style: NSWindow.StyleMask =
            titled
            ? [.titled, .closable, .nonactivatingPanel]
            : [.borderless, .nonactivatingPanel]
        super.init(contentRect: frame, styleMask: style, backing: .buffered, defer: false)
        isFloatingPanel = true
        level = .floating
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isReleasedWhenClosed = false
        isOpaque = false
        backgroundColor = .clear
        contentView = NSHostingView(rootView: content)
    }

    /// Stored capture rectangles use a top-left origin on the primary display.
    static func appKitFrame(for globalCGRect: CGRect) -> CGRect {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        return CGRect(
            x: globalCGRect.minX,
            y: primaryHeight - globalCGRect.minY - globalCGRect.height,
            width: globalCGRect.width, height: globalCGRect.height)
    }

    static func screen(containing selection: CGRect) -> NSScreen? {
        let frame = appKitFrame(for: selection)
        let center = CGPoint(x: frame.midX, y: frame.midY)
        return NSScreen.screens.first { $0.frame.contains(center) }
            ?? NSScreen.screens.max {
                let lhs = $0.frame.intersection(frame)
                let rhs = $1.frame.intersection(frame)
                return (lhs.isNull ? 0 : lhs.width * lhs.height)
                    < (rhs.isNull ? 0 : rhs.width * rhs.height)
            }
    }

    static func clampedFrame(_ frame: CGRect, to visibleFrame: CGRect) -> CGRect {
        let size = CGSize(
            width: min(frame.width, visibleFrame.width),
            height: min(frame.height, visibleFrame.height))
        return CGRect(
            x: min(max(frame.minX, visibleFrame.minX), visibleFrame.maxX - size.width),
            y: min(max(frame.minY, visibleFrame.minY), visibleFrame.maxY - size.height),
            width: size.width, height: size.height)
    }

    static func frameBeside(
        selection: CGRect, visibleFrame: CGRect, size: CGSize, minimumSize: CGSize, avoiding: CGRect? = nil
    ) -> CGRect {
        let rect = appKitFrame(for: selection)
        let gap: CGFloat = 8
        if let avoiding {
            // Search free regions on all displays, preferring the closest frame to the selection.
            var choices: [(frame: CGRect, distance: CGFloat, preference: Int)] = []
            for screen in NSScreen.screens {
                let bounds = screen.visibleFrame
                let obstacles = [rect, avoiding].filter { $0.intersects(bounds) }
                let xs =
                    ([bounds.minX, bounds.maxX]
                    + obstacles.flatMap {
                        [max(bounds.minX, $0.minX - gap), min(bounds.maxX, $0.maxX + gap)]
                    }).sorted()
                let ys =
                    ([bounds.minY, bounds.maxY]
                    + obstacles.flatMap {
                        [max(bounds.minY, $0.minY - gap), min(bounds.maxY, $0.maxY + gap)]
                    }).sorted()
                for left in xs {
                    for right in xs where right - left >= minimumSize.width {
                        for bottom in ys {
                            for top in ys where top - bottom >= minimumSize.height {
                                let region = CGRect(x: left, y: bottom, width: right - left, height: top - bottom)
                                guard !obstacles.contains(where: { $0.intersects(region) }) else { continue }
                                let desired = [
                                    CGPoint(x: rect.maxX + gap, y: rect.maxY - size.height),
                                    CGPoint(x: rect.minX - gap - size.width, y: rect.maxY - size.height),
                                    CGPoint(x: rect.minX, y: rect.minY - gap - size.height),
                                    CGPoint(x: rect.minX, y: rect.maxY + gap),
                                ]
                                for origin in desired {
                                    let frame = clampedFrame(CGRect(origin: origin, size: size), to: region)
                                    let dx = max(rect.minX - frame.maxX, frame.minX - rect.maxX, 0)
                                    let dy = max(rect.minY - frame.maxY, frame.minY - rect.maxY, 0)
                                    let preference: Int
                                    if frame.minX >= rect.maxX {
                                        preference = 0
                                    } else if frame.maxX <= rect.minX {
                                        preference = 1
                                    } else if frame.maxY <= rect.minY {
                                        preference = 2
                                    } else {
                                        preference = 3
                                    }
                                    choices.append((frame, dx * dx + dy * dy, preference))
                                }
                            }
                        }
                    }
                }
            }
            if let best = choices.min(by: {
                $0.distance == $1.distance ? $0.preference < $1.preference : $0.distance < $1.distance
            }) {
                return best.frame
            }
        }
        let candidates = [
            CGRect(x: rect.maxX + gap, y: rect.maxY - size.height, width: size.width, height: size.height),
            CGRect(x: rect.minX - gap - size.width, y: rect.maxY - size.height, width: size.width, height: size.height),
            CGRect(x: rect.minX, y: rect.minY - gap - size.height, width: size.width, height: size.height),
            CGRect(x: rect.minX, y: rect.maxY + gap, width: size.width, height: size.height),
        ]
        for candidate in candidates {
            let frame = clampedFrame(candidate, to: visibleFrame)
            if !frame.intersects(rect) { return frame }
        }
        let regions = [
            CGRect(
                x: rect.maxX + gap, y: visibleFrame.minY, width: max(0, visibleFrame.maxX - rect.maxX - gap),
                height: visibleFrame.height),
            CGRect(
                x: visibleFrame.minX, y: visibleFrame.minY, width: max(0, rect.minX - gap - visibleFrame.minX),
                height: visibleFrame.height),
            CGRect(
                x: visibleFrame.minX, y: visibleFrame.minY, width: visibleFrame.width,
                height: max(0, rect.minY - gap - visibleFrame.minY)),
            CGRect(
                x: visibleFrame.minX, y: rect.maxY + gap, width: visibleFrame.width,
                height: max(0, visibleFrame.maxY - rect.maxY - gap)),
        ]
        if let region = regions.filter({ $0.width >= minimumSize.width && $0.height >= minimumSize.height })
            .max(by: { $0.width * $0.height < $1.width * $1.height })
        {
            return clampedFrame(CGRect(origin: region.origin, size: size), to: region)
        }
        // A second display can provide room when the selection fills this screen.
        for screen in NSScreen.screens where screen.visibleFrame != visibleFrame {
            let available = screen.visibleFrame
            guard available.width >= minimumSize.width, available.height >= minimumSize.height else { continue }
            let frame = clampedFrame(candidates[0], to: available)
            if !frame.intersects(rect) { return frame }
        }
        return clampedFrame(candidates[0], to: visibleFrame)
    }

    static func clampedFrame(_ frame: CGRect, for selection: CGRect) -> CGRect {
        guard let screen = screen(containing: selection) else { return frame }
        return clampedFrame(frame, to: screen.visibleFrame)
    }
}
