import Foundation

@MainActor
struct Translator {
    let settings: AppSettings

    func translate(from capture: CaptureResult) -> AsyncThrowingStream<String, Error> {
        let language = settings.targetLanguage
        return ImageTextRequest.stream(capture: capture, settings: settings, prompt: "Read all text in the image and translate it into \(language). Preserve the layout (line breaks, lists). Output only the translation, no commentary. If the text is already in \(language), output it unchanged.")
    }
}
