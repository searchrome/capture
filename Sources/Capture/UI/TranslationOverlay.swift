import AppKit
import SwiftUI

@MainActor
private final class OverlayState: ObservableObject {
    @Published var blocks: [TranslationBlock] = []
    @Published var status = "Recognizing text…"
    @Published var error: String?
    @Published var missingKey = false
    @Published var finished = false
    var source = "Original"
    var target = "English"
    var fullTranslation: String { blocks.compactMap(\.translation).joined(separator: "\n\n") }
    var original: String { blocks.map(\.original).joined(separator: "\n\n") }
    var hasMissingBlocks: Bool { finished && blocks.contains { $0.translation == nil } }
}

@MainActor
final class TranslationOverlay {
    private let state = OverlayState()
    private let capture: CaptureResult
    private let settings: AppSettings
    private let openSettings: () -> Void
    private let openText: (String) -> Void
    private let fallback: () -> Void
    private var overlay: FloatingPanel?
    private var pill: FloatingPanel?
    private var task: Task<Void, Never>?
    private var canvas: TranslationCanvas?

    init(
        capture: CaptureResult,
        settings: AppSettings,
        openSettings: @escaping () -> Void,
        openText: @escaping (String) -> Void,
        fallback: @escaping () -> Void
    ) {
        self.capture = capture
        self.settings = settings
        self.openSettings = openSettings
        self.openText = openText
        self.fallback = fallback
    }

    var windows: [NSWindow] { [overlay, pill].compactMap { $0 } }

    func show() {
        guard let screen = NSScreen.screens.first(where: { $0.captureDisplayID == capture.displayID })
                ?? FloatingPanel.screen(containing: capture.rect) else { return }
        state.target = settings.targetLanguage
        let view = TranslationCanvas(capture: capture, state: state)
        view.copyTranslation = { [weak self] in self?.copy(self?.state.fullTranslation ?? "") }
        view.copyOriginal = { [weak self] in self?.copy(self?.state.original ?? "") }
        view.openText = { [weak self] in self?.openAsText() }
        view.closeOverlay = { [weak self] in self?.close() }
        let window = FloatingPanel(frame: FloatingPanel.appKitFrame(for: capture.rect), content: EmptyView())
        window.contentView = view
        window.acceptsMouseMovedEvents = true
        window.hasShadow = false
        window.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 1)
        window.identifier = NSUserInterfaceItemIdentifier("debugTranslationOverlay")
        overlay = window
        canvas = view

        let pillSize = CGSize(width: 620, height: 42)
        let barFrame = ActionBar.frame(for: capture.rect, visibleFrame: screen.visibleFrame)
        let below = CGRect(
            x: barFrame.maxX - pillSize.width, y: barFrame.minY - pillSize.height - 6,
            width: pillSize.width, height: pillSize.height
        )
        let above = CGRect(
            x: barFrame.maxX - pillSize.width, y: barFrame.maxY + 6,
            width: pillSize.width, height: pillSize.height
        )
        let candidate = below.minY >= screen.visibleFrame.minY ? below : above
        let pillView = TranslationPill(
            state: state,
            copyTranslation: { [weak self] in self?.copy(self?.state.fullTranslation ?? "") },
            copyOriginal: { [weak self] in self?.copy(self?.state.original ?? "") },
            open: { [weak self] in self?.openAsText() },
            settings: openSettings,
            close: { [weak self] in self?.close() }
        )
        let pillWindow = FloatingPanel(
            frame: FloatingPanel.clampedFrame(candidate, to: screen.visibleFrame), content: pillView
        )
        pillWindow.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 2)
        pillWindow.identifier = NSUserInterfaceItemIdentifier("debugTranslationPill")
        pill = pillWindow
        window.orderFrontRegardless()
        pillWindow.orderFrontRegardless()
        startTranslation()
    }

    private func startTranslation() {
        task = Task { [weak self] in
            guard let self else { return }
            do {
                let translator = InPlaceTranslator(settings: self.settings)
                let layout = try await translator.layout(for: self.capture)
                try Task.checkCancellation()
                guard !layout.blocks.isEmpty else {
                    self.close()
                    self.fallback()
                    return
                }
                self.state.blocks = layout.blocks
                self.state.source = layout.sourceLanguage
                self.canvas?.startShimmer()
                self.updateStatus()
                try await translator.translate(layout.blocks, target: self.state.target) { [weak self] index, text in
                    self?.publish(index: index, text: text)
                }
                try Task.checkCancellation()
                self.state.finished = true
                self.canvas?.stopShimmer()
                self.updateStatus()
                self.canvas?.needsDisplay = true
                if self.settings.autoCopy { self.copy(self.state.fullTranslation) }
                #if DEBUG
                self.writeSnapshot()
                #endif
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                self.state.error = error.localizedDescription
                if case OpenRouterError.missingAPIKey = error { self.state.missingKey = true }
                self.canvas?.stopShimmer()
                self.canvas?.needsDisplay = true
            }
        }
    }

    private func publish(index: Int, text: String) {
        guard state.blocks.indices.contains(index) else { return }
        state.blocks[index].translation = text
        if state.blocks.allSatisfy({ $0.translation != nil }) {
            canvas?.stopShimmer()
        }
        updateStatus()
        canvas?.refreshToolTips()
        canvas?.needsDisplay = true
    }

    private func updateStatus() {
        let done = state.blocks.filter { $0.translation != nil }.count
        guard state.finished else {
            state.status = "Translating… \(done)/\(state.blocks.count)"
            return
        }
        let missing = state.blocks.count - done
        if missing > 0 {
            let noun = missing == 1 ? "block was" : "blocks were"
            state.status = "\(missing) of \(state.blocks.count) \(noun) not translated"
        } else if state.source.caseInsensitiveCompare(state.target) == .orderedSame {
            state.status = "Already in \(state.target) · hold to see original"
        } else {
            state.status = "\(state.source) → \(state.target) · hold to see original"
        }
    }

    private func copy(_ text: String) {
        guard !text.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func openAsText() {
        openText(state.fullTranslation)
    }

    func close() {
        task?.cancel()
        task = nil
        canvas?.stop()
        canvas = nil
        overlay?.close()
        overlay = nil
        pill?.close()
        pill = nil
    }

    #if DEBUG
    private func writeSnapshot() {
        let entries: [[String: Any]] = state.blocks.enumerated().map { index, block in
            let colors = canvas?.colors(for: block.rect, index: index)
            return [
                "original": block.original,
                "translation": block.translation ?? "",
                "rect": [
                    "x": block.rect.minX, "y": block.rect.minY,
                    "width": block.rect.width, "height": block.rect.height
                ],
                "background": colors?.0.debugComponents ?? [],
                "textColor": colors?.1.debugComponents ?? []
            ]
        }
        if let data = try? JSONSerialization.data(withJSONObject: entries, options: [.prettyPrinted, .sortedKeys]),
           let json = String(data: data, encoding: .utf8) {
            DebugSnapshots.writeText(json, file: "overlay.json")
        }
        DispatchQueue.main.async { DebugSnapshots.write(name: "overlay") }
    }
    #endif
}

@MainActor
private struct TranslationPill: View {
    @ObservedObject var state: OverlayState
    let copyTranslation: () -> Void
    let copyOriginal: () -> Void
    let open: () -> Void
    let settings: () -> Void
    let close: () -> Void
    @State private var copied: CopyKind?
    @State private var copyReset: Task<Void, Never>?

    private enum CopyKind { case translation, original }

    private func copy(_ kind: CopyKind) {
        switch kind {
        case .translation: copyTranslation()
        case .original: copyOriginal()
        }
        copied = kind
        copyReset?.cancel()
        copyReset = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard !Task.isCancelled else { return }
            copied = nil
        }
    }

    private var statusColor: Color {
        if state.error != nil { return .red }
        return state.hasMissingBlocks ? .orange : .primary
    }

    var body: some View {
        HStack(spacing: 8) {
            Text(state.error ?? state.status)
                .font(.caption)
                .lineLimit(2)
                .foregroundStyle(statusColor)
            Spacer(minLength: 2)
            if state.missingKey {
                Button("Open Settings", action: settings)
            }
            Button(copied == .translation ? "Copied ✓" : "Copy translation") {
                copy(.translation)
            }.disabled(state.fullTranslation.isEmpty)
            Button(copied == .original ? "Copied ✓" : "Copy original") {
                copy(.original)
            }.disabled(state.original.isEmpty)
            Button("Open as text", action: open).disabled(state.fullTranslation.isEmpty)
            Button("Close", action: close)
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
    }
}

@MainActor
private final class TranslationCanvas: NSView, NSViewToolTipOwner {
    private let capture: CaptureResult
    private let state: OverlayState
    private let pixels: ImagePixels
    private var shimmerTimer: Timer?
    private var modifierTimer: Timer?
    private var held = false
    private var optionHeld = NSEvent.modifierFlags.contains(.option)
    private var phase: CGFloat = 0
    private var colorCache: [String: (NSColor, NSColor)] = [:]
    private var toolTipText: [NSView.ToolTipTag: String] = [:]
    private var mouseTracking: NSTrackingArea?
    var copyTranslation: () -> Void = {}
    var copyOriginal: () -> Void = {}
    var openText: () -> Void = {}
    var closeOverlay: () -> Void = {}
    override var isFlipped: Bool { true }

    init(capture: CaptureResult, state: OverlayState) {
        self.capture = capture
        self.state = state
        self.pixels = ImagePixels(image: capture.image)
        super.init(frame: CGRect(origin: .zero, size: capture.rect.size))
        modifierTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.checkModifier() }
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func startShimmer() {
        shimmerTimer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.advanceShimmer() }
        }
    }

    private func advanceShimmer() {
        guard shimmerTimer != nil else { return }
        phase += 0.08
        needsDisplay = true
    }

    private func checkModifier() {
        let isHeld = NSEvent.modifierFlags.contains(.option)
        guard isHeld != optionHeld else { return }
        optionHeld = isHeld
        needsDisplay = true
    }

    func stopShimmer() {
        shimmerTimer?.invalidate()
        shimmerTimer = nil
    }

    func stop() {
        stopShimmer()
        modifierTimer?.invalidate()
        modifierTimer = nil
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .arrow) }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let mouseTracking { removeTrackingArea(mouseTracking) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseMoved, .activeAlways, .inVisibleRect],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        mouseTracking = area
    }

    func refreshToolTips() {
        removeAllToolTips()
        toolTipText.removeAll()
        for (index, block) in state.blocks.enumerated() {
            guard let translation = block.translation else { continue }
            let lines = translation.components(separatedBy: .newlines)
            if lines.count == block.lines.count {
                let drawings = lineDrawings(lines, block: block, index: index)
                for (line, drawing) in zip(block.lines, drawings) {
                    let tag = addToolTip(drawing.patch, owner: self, userData: nil)
                    toolTipText[tag] = line.text
                }
            } else {
                let rect = blockTextLayout(translation, in: block.rect, fontSize: block.estimatedFontSize,
                                           centered: block.centered, colors: colors(for: block.rect, index: index)).rect
                let tag = addToolTip(rect.insetBy(dx: -2, dy: -2), owner: self, userData: nil)
                toolTipText[tag] = block.original
            }
        }
    }

    func view(_ view: NSView, stringForToolTip tag: NSView.ToolTipTag, point: NSPoint,
              userData data: UnsafeMutableRawPointer?) -> String {
        toolTipText[tag] ?? ""
    }

    override func mouseDown(with event: NSEvent) {
        held = true
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        held = false
        needsDisplay = true
    }

    override func rightMouseDown(with event: NSEvent) {
        let menu = NSMenu()
        let actions: [(String, Selector)] = [
            ("Copy translation", #selector(copyTranslationAction)),
            ("Copy original", #selector(copyOriginalAction)),
            ("Open as text", #selector(openAction)),
            ("Close", #selector(closeAction))
        ]
        for (title, selector) in actions {
            let item = NSMenuItem(title: title, action: selector, keyEquivalent: "")
            item.target = self
            menu.addItem(item)
        }
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    @objc private func copyTranslationAction() { copyTranslation() }
    @objc private func copyOriginalAction() { copyOriginal() }
    @objc private func openAction() { openText() }
    @objc private func closeAction() { closeOverlay() }

    func colors(for rect: CGRect, index: Int, line: Int? = nil) -> (NSColor, NSColor) {
        let key = "\(index):\(line.map(String.init) ?? "block")"
        if let cached = colorCache[key] { return cached }
        let result = pixels.colors(rect: rect, size: bounds.size)
        colorCache[key] = result
        return result
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        NSImage(cgImage: capture.image, size: bounds.size).draw(
            in: bounds, from: .zero, operation: .copy, fraction: 1, respectFlipped: true, hints: nil
        )
        guard !held, !optionHeld else { return }
        for (index, block) in state.blocks.enumerated() {
            guard let translation = block.translation else {
                if shimmerTimer != nil { drawShimmer(in: block.rect) }
                continue
            }
            let lines = translation.components(separatedBy: .newlines)
            if lines.count == block.lines.count {
                let drawings = lineDrawings(lines, block: block, index: index)
                for drawing in drawings {
                    drawing.background.setFill()
                    NSBezierPath(roundedRect: drawing.patch, xRadius: 2, yRadius: 2).fill()
                }
                for drawing in drawings {
                    (drawing.text as NSString).draw(
                        with: drawing.textRect,
                        options: [.usesLineFragmentOrigin, .usesFontLeading, .truncatesLastVisibleLine],
                        attributes: drawing.attributes
                    )
                }
            } else {
                drawText(
                    translation, in: block.rect, fontSize: block.estimatedFontSize, centered: block.centered,
                    colors: colors(for: block.rect, index: index)
                )
            }
        }
    }

    private func drawShimmer(in rect: CGRect) {
        NSColor.white.withAlphaComponent(0.08 + 0.07 * (1 + sin(phase * 3)) / 2).setFill()
        NSBezierPath(roundedRect: rect.insetBy(dx: -2, dy: -2), xRadius: 2, yRadius: 2).fill()
    }

    private func availableSpace(
        for rect: CGRect, blockIndex: Int, lineIndex: Int, background: NSColor,
        centered: Bool, singleLine: Bool
    ) -> (rect: CGRect, centered: Bool) {
        var leftEdge = bounds.minX + 4
        var rightEdge = bounds.maxX - 4
        for (otherBlockIndex, block) in state.blocks.enumerated() {
            var obstacles = block.lines.enumerated().compactMap { otherLineIndex, line in
                otherBlockIndex == blockIndex && otherLineIndex == lineIndex ? nil : line.rect
            }
            if otherBlockIndex != blockIndex { obstacles.append(block.rect) }
            for obstacle in obstacles where obstacle.minY < rect.maxY && obstacle.maxY > rect.minY {
                if obstacle.minX > rect.minX { rightEdge = min(rightEdge, obstacle.minX - 6) }
                if obstacle.maxX < rect.maxX { leftEdge = max(leftEdge, obstacle.maxX + 6) }
            }
        }
        let rightBoundary = pixels.backgroundEdge(
            from: rect, size: bounds.size, background: background, limit: rightEdge, direction: 1
        )
        let leftBoundary = centered || singleLine ? pixels.backgroundEdge(
            from: rect, size: bounds.size, background: background, limit: leftEdge, direction: -1
        ) : nil
        let symmetric = centered || (singleLine && leftBoundary != nil && rightBoundary != nil)
        if let rightBoundary { rightEdge = min(rightEdge, rightBoundary - 4) }
        if symmetric, let leftBoundary { leftEdge = max(leftEdge, leftBoundary + 4) }
        leftEdge = symmetric ? min(rect.minX, leftEdge) : rect.minX
        rightEdge = max(rect.maxX, rightEdge)
        return (CGRect(x: leftEdge, y: rect.minY, width: rightEdge - leftEdge, height: rect.height), symmetric)
    }

    private struct LineDrawing {
        let text: String
        let textRect: CGRect
        let patch: CGRect
        let background: NSColor
        let attributes: [NSAttributedString.Key: Any]
    }

    private func lineDrawings(_ lines: [String], block: TranslationBlock, index: Int) -> [LineDrawing] {
        let sizes = block.lines.map(\.estimatedFontSize).sorted()
        return block.lines.enumerated().map { lineIndex, line in
            let similarSizes = sizes.filter { abs($0 - line.estimatedFontSize) <= line.estimatedFontSize * 0.25 }
            let middle = similarSizes.count / 2
            let median = similarSizes.count.isMultiple(of: 2)
                ? (similarSizes[middle - 1] + similarSizes[middle]) / 2 : similarSizes[middle]
            let lineColors = colors(for: line.rect, index: index, line: lineIndex)
            let space = availableSpace(
                for: line.rect, blockIndex: index, lineIndex: lineIndex,
                background: lineColors.0, centered: block.centered, singleLine: block.lines.count == 1
            )
            return prepareLine(lines[lineIndex], in: line.rect, available: space.rect,
                               fontSize: median, centered: space.centered, colors: lineColors)
        }
    }

    private func prepareLine(
        _ text: String, in rect: CGRect, available: CGRect, fontSize: CGFloat,
        centered: Bool, colors: (NSColor, NSColor)
    ) -> LineDrawing {
        let availableWidth = available.width
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        let originalSize = fontSize
        var size = originalSize
        func attributes() -> [NSAttributedString.Key: Any] {
            [.font: NSFont.systemFont(ofSize: size), .foregroundColor: colors.1, .paragraphStyle: paragraph]
        }
        var measured = (text as NSString).size(withAttributes: attributes())
        if measured.width > availableWidth {
            var lower = originalSize * 0.85
            var upper = originalSize
            size = lower
            measured = (text as NSString).size(withAttributes: attributes())
            if measured.width <= availableWidth {
                for _ in 0..<8 {
                    size = (lower + upper) / 2
                    if (text as NSString).size(withAttributes: attributes()).width <= availableWidth {
                        lower = size
                    } else {
                        upper = size
                    }
                }
                size = lower
                measured = (text as NSString).size(withAttributes: attributes())
            }
        }
        let width = min(availableWidth, ceil(measured.width))
        let x = centered ? available.midX - width / 2 : rect.minX
        let font = NSFont.systemFont(ofSize: size)
        let height = font.ascender - font.descender + font.leading
        let textRect = CGRect(x: x, y: rect.midY - height / 2, width: width, height: height)
        return LineDrawing(
            text: text, textRect: textRect, patch: rect.union(textRect).insetBy(dx: -2, dy: -2),
            background: colors.0, attributes: attributes()
        )
    }

    private func drawText(
        _ text: String, in rect: CGRect, fontSize: CGFloat, centered: Bool,
        colors: (NSColor, NSColor)
    ) {
        let layout = blockTextLayout(text, in: rect, fontSize: fontSize, centered: centered, colors: colors)
        colors.0.setFill()
        NSBezierPath(roundedRect: layout.rect.insetBy(dx: -2, dy: -2), xRadius: 2, yRadius: 2).fill()
        (text as NSString).draw(
            with: layout.rect, options: [.usesLineFragmentOrigin, .usesFontLeading, .truncatesLastVisibleLine],
            attributes: layout.attributes
        )
    }

    private func blockTextLayout(
        _ text: String, in rect: CGRect, fontSize: CGFloat, centered: Bool,
        colors: (NSColor, NSColor)
    ) -> (rect: CGRect, attributes: [NSAttributedString.Key: Any]) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = centered ? .center : .left
        paragraph.lineBreakMode = .byWordWrapping
        var size = fontSize
        var attributes: [NSAttributedString.Key: Any] = [:]
        func measure() -> CGRect {
            attributes = [
                .font: NSFont.systemFont(ofSize: size), .foregroundColor: colors.1, .paragraphStyle: paragraph
            ]
            return (text as NSString).boundingRect(
                with: CGSize(width: max(1, rect.width), height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: attributes
            )
        }
        var measured = measure()
        while measured.height > rect.height && size > 7 {
            size = max(7, size - 0.5)
            measured = measure()
        }
        let height = min(max(rect.height, measured.height), rect.height * 1.4, bounds.maxY - rect.minY)
        let textRect = CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: max(0, height))
        if measured.height > height { paragraph.lineBreakMode = .byTruncatingTail }
        return (textRect, attributes)
    }
}

private extension NSColor {
    var debugComponents: [CGFloat] {
        let color = usingColorSpace(.deviceRGB) ?? self
        return [color.redComponent, color.greenComponent, color.blueComponent]
    }
}

private struct ImagePixels {
    let width: Int
    let height: Int
    let data: [UInt8]

    init(image: CGImage) {
        width = image.width
        height = image.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        if let context = CGContext(
            data: &bytes, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) {
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        data = bytes
    }

    func colors(rect: CGRect, size: CGSize) -> (NSColor, NSColor) {
        guard size.width > 0, size.height > 0, width > 0, height > 0 else { return (.white, .black) }
        let x0 = max(0, min(width - 1, Int(rect.minX / size.width * CGFloat(width))))
        let x1 = max(x0 + 1, min(width, Int(ceil(rect.maxX / size.width * CGFloat(width)))))
        let y0 = max(0, min(height - 1, Int(rect.minY / size.height * CGFloat(height))))
        let y1 = max(y0 + 1, min(height, Int(ceil(rect.maxY / size.height * CGFloat(height)))))
        var ring: [[Double]] = []
        func add(_ x: Int, _ y: Int) {
            guard x >= 0, x < width, y >= 0, y < height else { return }
            ring.append(pixel(x, y))
        }
        for y in (y0 - 3)..<(y1 + 3) {
            for x in [x0 - 3, x0 - 2, x1 + 1, x1 + 2] { add(x, y) }
        }
        for x in x0..<x1 {
            for y in [y0 - 3, y0 - 2, y1 + 1, y1 + 2] { add(x, y) }
        }
        if ring.isEmpty { ring = [pixel(x0, y0)] }
        let background = (0..<3).map { channel in
            let values = ring.map { $0[channel] }.sorted()
            return values[values.count / 2]
        }
        let backgroundLuminance = luminance(background)
        var best = background
        var distance = 0.0
        for y in y0..<y1 {
            for x in x0..<x1 {
                let candidate = pixel(x, y)
                let difference = abs(luminance(candidate) - backgroundLuminance)
                if difference > distance {
                    distance = difference
                    best = candidate
                }
            }
        }
        if contrast(luminance(best), backgroundLuminance) < 3.0 {
            best = contrast(0, backgroundLuminance) > contrast(1, backgroundLuminance) ? [0, 0, 0] : [1, 1, 1]
        }
        return (color(background), color(best))
    }

    func backgroundEdge(
        from rect: CGRect, size: CGSize, background: NSColor, limit: CGFloat, direction: Int
    ) -> CGFloat? {
        guard size.width > 0, size.height > 0, width > 0, height > 0,
              let rgb = background.usingColorSpace(.deviceRGB) else { return nil }
        let scaleX = CGFloat(width) / size.width
        let scaleY = CGFloat(height) / size.height
        let y0 = max(0, min(height - 1, Int(floor((rect.minY + rect.height * 0.15) * scaleY))))
        let y1 = max(y0 + 1, min(height, Int(ceil((rect.maxY - rect.height * 0.15) * scaleY))))
        let reference = [Double(rgb.redComponent), Double(rgb.greenComponent), Double(rgb.blueComponent)]
        var x = direction > 0 ? Int(ceil(rect.maxX * scaleX)) : Int(floor(rect.minX * scaleX)) - 1
        while x >= 0 && x < width {
            let edge = CGFloat(direction > 0 ? x : x + 1) / scaleX
            if direction > 0 ? edge >= limit : edge <= limit { break }
            var channels = [[Double]](repeating: [], count: 3)
            for y in y0..<y1 {
                let value = pixel(x, y)
                for channel in 0..<3 { channels[channel].append(value[channel]) }
            }
            let distance = (0..<3).reduce(0.0) { sum, channel in
                let values = channels[channel].sorted()
                let difference = values[values.count / 2] - reference[channel]
                return sum + difference * difference
            }
            if distance > 0.12 * 0.12 { return edge }
            x += direction
        }
        return nil
    }

    private func pixel(_ x: Int, _ y: Int) -> [Double] {
        let index = (y * width + x) * 4
        return (0..<3).map { Double(data[index + $0]) / 255 }
    }

    private func luminance(_ rgb: [Double]) -> Double {
        let components = rgb.map { $0 <= 0.04045 ? $0 / 12.92 : pow(($0 + 0.055) / 1.055, 2.4) }
        return components[0] * 0.2126 + components[1] * 0.7152 + components[2] * 0.0722
    }

    private func contrast(_ a: Double, _ b: Double) -> Double {
        (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }

    private func color(_ rgb: [Double]) -> NSColor {
        NSColor(deviceRed: rgb[0], green: rgb[1], blue: rgb[2], alpha: 1)
    }
}
