import AppKit
import Foundation
import NaturalLanguage
import Vision

struct TranslationBlock {
    var original: String
    var lines: [(text: String, rect: CGRect, estimatedFontSize: CGFloat)]
    var rect: CGRect
    var estimatedFontSize: CGFloat
    var centered: Bool
    var translation: String?
}

struct InPlaceLayout {
    var blocks: [TranslationBlock]
    var sourceLanguage: String
}

@MainActor
struct InPlaceTranslator {
    private static let descenders = Set("gjpqyçşğ,;()[]{}|ÇŞQJ")
    private static let fontRatios: (ascender: CGFloat, full: CGFloat) = {
        let font = NSFont.systemFont(ofSize: 100)
        return (font.ascender / font.pointSize, (font.ascender - font.descender) / font.pointSize)
    }()

    let settings: AppSettings

    func layout(for capture: CaptureResult) async throws -> InPlaceLayout {
        let ratios = Self.fontRatios
        let descenders = Self.descenders
        let task = Task.detached { () throws -> InPlaceLayout in
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.automaticallyDetectsLanguage = true
            try VNImageRequestHandler(cgImage: capture.image).perform([request])
            try Task.checkCancellation()

            let lines: [(text: String, rect: CGRect, estimatedFontSize: CGFloat)] = (request.results ?? []).compactMap { observation in
                guard let text = observation.topCandidates(1).first?.string, !text.isEmpty else {
                    return nil
                }
                let box = observation.boundingBox
                let rect = CGRect(
                    x: box.minX * capture.rect.width,
                    y: (1 - box.maxY) * capture.rect.height,
                    width: box.width * capture.rect.width,
                    height: box.height * capture.rect.height
                )
                let ratio = text.contains { descenders.contains($0) } ? ratios.full : ratios.ascender
                let estimatedFontSize = min(72, max(7, rect.height / ratio))
                return (text, rect, estimatedFontSize)
            }.sorted {
                $0.rect.minY == $1.rect.minY ? $0.rect.minX < $1.rect.minX : $0.rect.minY < $1.rect.minY
            }
            let blocks = Self.makeBlocks(from: lines)
            let recognizer = NLLanguageRecognizer()
            recognizer.processString(blocks.map(\.original).joined(separator: " "))
            let source = recognizer.dominantLanguage.flatMap {
                Locale.current.localizedString(forLanguageCode: $0.rawValue)
            } ?? "Original"
            return InPlaceLayout(blocks: blocks, sourceLanguage: source.capitalized)
        }
        return try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
    }

    private nonisolated static func makeBlocks(
        from lines: [(text: String, rect: CGRect, estimatedFontSize: CGFloat)]
    ) -> [TranslationBlock] {
        var groups: [[(text: String, rect: CGRect, estimatedFontSize: CGFloat)]] = []
        for line in lines {
            let candidates = groups.indices.filter { index in
                guard let last = groups[index].last else { return false }
                let a = last.rect
                let b = line.rect
                let gap = b.minY - a.maxY
                return gap >= -min(a.height, b.height) * 0.2
                    && gap < max(a.height, b.height) * 0.8
                    && abs(a.minX - b.minX) <= max(a.height, b.height)
                    && line.estimatedFontSize >= last.estimatedFontSize * 0.8
                    && line.estimatedFontSize <= last.estimatedFontSize * 1.25
            }
            let closest = candidates.min { first, second in
                abs(groups[first].last!.rect.maxY - line.rect.minY)
                    < abs(groups[second].last!.rect.maxY - line.rect.minY)
            }
            if let closest {
                groups[closest].append(line)
            } else {
                groups.append([line])
            }
        }
        return groups.map(makeBlock)
    }

    private nonisolated static func makeBlock(
        from group: [(text: String, rect: CGRect, estimatedFontSize: CGFloat)]
    ) -> TranslationBlock {
        let sizes = group.map(\.estimatedFontSize).sorted()
        let estimatedFontSize = sizes[sizes.count / 2]
        let rect = group.dropFirst().reduce(group[0].rect) { $0.union($1.rect) }
        let centers = group.map { $0.rect.midX }
        let edges = group.map { $0.rect.minX }
        let centered = group.count > 1 && (centers.max()! - centers.min()!) < estimatedFontSize * 0.5
            && (edges.max()! - edges.min()!) > estimatedFontSize * 0.3
        return TranslationBlock(
            original: group.map(\.text).joined(separator: "\n"),
            lines: group,
            rect: rect,
            estimatedFontSize: estimatedFontSize,
            centered: centered
        )
    }

    func translate(
        _ blocks: [TranslationBlock],
        target: String,
        publish: @escaping (Int, String) -> Void
    ) async throws {
        #if DEBUG
        if UserDefaults.standard.bool(forKey: "debugFakeTranslation") {
            for (index, block) in blocks.enumerated() {
                try await Task.sleep(nanoseconds: 150_000_000)
                let text = block.lines.map { "[EN] " + String($0.text.reversed()) }.joined(separator: "\n")
                publish(index, text)
            }
            return
        }
        #endif
        let prompt = """
        Translate each numbered block into \(target); keep meaning across blocks; keep numbers, names, codes, URLs. \
        If lines in a block are separate items (headings, labels, list entries, table cells, address or invoice \
        lines), return exactly the same number of lines in the same order. If they form one wrapped sentence or \
        paragraph, return flowing text. Output exactly one section per block in the same order, each starting on \
        its own line with the marker ⟦n⟧ followed by the translation; no other text.
        """
        let input = blocks.enumerated().map { "⟦\($0.offset + 1)⟧ \($0.element.original)" }
            .joined(separator: "\n")
        let request = ChatRequest(
            model: settings.visionModel,
            messages: [
                ChatMessage(role: .system, content: .text(prompt)),
                ChatMessage(role: .user, content: .text(input))
            ],
            temperature: 0,
            reasoning: settings.disableReasoning ? ["enabled": .bool(false)] : nil
        )
        let regex = try NSRegularExpression(pattern: "⟦([0-9]+)⟧")
        var buffer = ""
        var published = Set<Int>()
        func flush(final: Bool) {
            let matches = regex.matches(in: buffer, range: NSRange(buffer.startIndex..., in: buffer))
            for (position, match) in matches.enumerated() where final || position + 1 < matches.count {
                guard let numberRange = Range(match.range(at: 1), in: buffer),
                      let number = Int(buffer[numberRange]), number > 0, number <= blocks.count,
                      !published.contains(number),
                      let start = Range(match.range, in: buffer)?.upperBound else { continue }
                let end = position + 1 < matches.count
                    ? Range(matches[position + 1].range, in: buffer)!.lowerBound : buffer.endIndex
                let value = String(buffer[start..<end]).trimmingCharacters(in: .whitespacesAndNewlines)
                if !value.isEmpty {
                    published.insert(number)
                    publish(number - 1, value)
                }
            }
        }
        for try await event in OpenRouterClient().stream(request) {
            try Task.checkCancellation()
            if case .text(let delta) = event {
                buffer += delta
                flush(final: false)
            }
        }
        flush(final: true)
    }
}
