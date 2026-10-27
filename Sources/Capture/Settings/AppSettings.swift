import Combine
import Foundation

@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    enum OCREngine: String, Codable, CaseIterable {
        case llm
        case onDevice
    }

    enum TranslationDisplay: String, CaseIterable { case overlay, panel }

    static let languages = [
        "English", "Turkish", "German", "French", "Spanish", "Italian",
        "Portuguese", "Dutch", "Russian", "Ukrainian", "Polish", "Greek",
        "Arabic", "Persian", "Hebrew", "Hindi", "Chinese (Simplified)",
        "Chinese (Traditional)", "Japanese", "Korean", "Indonesian",
        "Vietnamese", "Thai", "Swedish"
    ]

    private let defaults: UserDefaults

    @Published var hotkey: Hotkey {
        didSet { defaults.set(try? JSONEncoder().encode(hotkey), forKey: "hotkey") }
    }
    @Published var visionModel: String { didSet { defaults.set(visionModel, forKey: "visionModel") } }
    @Published var chatModel: String { didSet { defaults.set(chatModel, forKey: "chatModel") } }
    @Published var disableReasoning: Bool { didSet { defaults.set(disableReasoning, forKey: "disableReasoning") } }
    @Published var targetLanguage: String { didSet { defaults.set(targetLanguage, forKey: "targetLanguage") } }
    @Published var ocrEngine: OCREngine { didSet { defaults.set(ocrEngine.rawValue, forKey: "ocrEngine") } }
    @Published var translationDisplay: TranslationDisplay { didSet { defaults.set(translationDisplay.rawValue, forKey: "translationDisplay") } }
    @Published var autoCopy: Bool { didSet { defaults.set(autoCopy, forKey: "autoCopy") } }
    @Published var maxImageSide: Int { didSet { defaults.set(maxImageSide, forKey: "maxImageSide") } }
    @Published var askBeforeActing: Bool { didSet { defaults.set(askBeforeActing, forKey: "askBeforeActing") } }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            "visionModel": "qwen/qwen3.7-flash", "chatModel": "qwen/qwen3.7-flash",
            "disableReasoning": true, "targetLanguage": "English",
            "ocrEngine": OCREngine.llm.rawValue, "translationDisplay": TranslationDisplay.overlay.rawValue, "autoCopy": true,
            "maxImageSide": 2048, "askBeforeActing": true
        ])
        hotkey = defaults.data(forKey: "hotkey")
            .flatMap { try? JSONDecoder().decode(Hotkey.self, from: $0) } ?? .default
        visionModel = defaults.string(forKey: "visionModel") ?? "qwen/qwen3.7-flash"
        chatModel = defaults.string(forKey: "chatModel") ?? "qwen/qwen3.7-flash"
        disableReasoning = defaults.bool(forKey: "disableReasoning")
        targetLanguage = defaults.string(forKey: "targetLanguage") ?? "English"
        ocrEngine = defaults.string(forKey: "ocrEngine").flatMap(OCREngine.init(rawValue:)) ?? .llm
        translationDisplay = defaults.string(forKey: "translationDisplay").flatMap(TranslationDisplay.init(rawValue:)) ?? .overlay
        autoCopy = defaults.bool(forKey: "autoCopy")
        maxImageSide = defaults.integer(forKey: "maxImageSide")
        askBeforeActing = defaults.bool(forKey: "askBeforeActing")
    }
}
