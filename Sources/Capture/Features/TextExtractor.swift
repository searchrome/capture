import Foundation
import Vision

@MainActor
struct TextExtractor {
    let settings: AppSettings

    func extract(from capture: CaptureResult) -> AsyncThrowingStream<String, Error> {
        if settings.ocrEngine == .llm {
            return ImageTextRequest.stream(capture: capture, settings: settings, prompt: "You are an OCR engine. Transcribe all text in the image exactly as written, preserving line breaks and reading order. Output only the text, no commentary. If there is no text, output nothing.")
        }
        return AsyncThrowingStream { continuation in
            let task = Task.detached {
                let request = VNRecognizeTextRequest()
                request.recognitionLevel = .accurate
                request.usesLanguageCorrection = true
                request.automaticallyDetectsLanguage = true
                request.revision = VNRecognizeTextRequest.supportedRevisions.last ?? VNRecognizeTextRequest.currentRevision
                do {
                    try await withTaskCancellationHandler {
                        try Task.checkCancellation()
                        try VNImageRequestHandler(cgImage: capture.image).perform([request])
                        try Task.checkCancellation()
                        let observations = request.results ?? []
                        // Vision coordinates have their origin at the lower left. Group overlapping
                        // boxes into rows, then read each row from left to right.
                        var rows: [[VNRecognizedTextObservation]] = []
                        for observation in observations.sorted(by: { $0.boundingBox.midY > $1.boundingBox.midY }) {
                            if let index = rows.firstIndex(where: { row in
                                row.contains { item in
                                    let a = item.boundingBox, b = observation.boundingBox
                                    return min(a.maxY, b.maxY) - max(a.minY, b.minY) > min(a.height, b.height) * 0.5
                                }
                            }) {
                                rows[index].append(observation)
                            } else {
                                rows.append([observation])
                            }
                        }
                        let text = rows.map { row in
                            row.sorted { $0.boundingBox.minX < $1.boundingBox.minX }
                                .compactMap { $0.topCandidates(1).first?.string }.joined(separator: " ")
                        }.joined(separator: "\n")
                        continuation.yield(text)
                        continuation.finish()
                    } onCancel: {
                        request.cancel()
                    }
                } catch { continuation.finish(throwing: error) }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

@MainActor
enum ImageTextRequest {
    static func stream(capture: CaptureResult, settings: AppSettings, prompt: String) -> AsyncThrowingStream<String, Error> {
        let image = capture.llmImage(maxSide: max(1, settings.maxImageSide)).png.base64EncodedString()
        let request = ChatRequest(model: settings.visionModel, messages: [
            ChatMessage(role: .system, content: .text(prompt)),
            ChatMessage(role: .user, content: .parts([.imageURL("data:image/png;base64,\(image)")]))
        ], temperature: 0, reasoning: settings.disableReasoning ? ["enabled": .bool(false)] : nil)
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for try await event in OpenRouterClient().stream(request) {
                        if case .text(let text) = event { continuation.yield(text) }
                    }
                    continuation.finish()
                } catch { continuation.finish(throwing: error) }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
