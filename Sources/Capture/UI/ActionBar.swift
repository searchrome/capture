import AppKit
import SwiftUI

@MainActor
struct ActionBar: View {
    @ObservedObject var settings: AppSettings
    let extractText: () -> Void
    let translate: () -> Void
    let openChat: () -> Void
    let openSettings: () -> Void
    let close: () -> Void

    static let size = CGSize(width: 284, height: 36)

    private static let languageCodes = [
        "English": "EN", "Turkish": "TR", "German": "DE", "French": "FR",
        "Spanish": "ES", "Italian": "IT", "Portuguese": "PT", "Dutch": "NL",
        "Russian": "RU", "Ukrainian": "UK", "Polish": "PL", "Greek": "EL",
        "Arabic": "AR", "Persian": "FA", "Hebrew": "HE", "Hindi": "HI",
        "Chinese (Simplified)": "ZH-Hans", "Chinese (Traditional)": "ZH-Hant",
        "Japanese": "JA", "Korean": "KO", "Indonesian": "ID",
        "Vietnamese": "VI", "Thai": "TH", "Swedish": "SV"
    ]

    var body: some View {
        HStack(spacing: 4) {
            iconButton("Image → Text", symbol: "text.viewfinder", action: extractText)
            iconButton("Translate", symbol: "translate", action: translate)
            Menu {
                Picker("Target language", selection: $settings.targetLanguage) {
                    ForEach(AppSettings.languages, id: \.self) { language in
                        Text(language).tag(language)
                    }
                }
                .pickerStyle(.inline)
            } label: {
                Text(Self.languageCodes[settings.targetLanguage] ?? String(settings.targetLanguage.prefix(2)).uppercased())
                    .font(.system(size: 11, weight: .semibold))
            }
            .menuStyle(.borderlessButton)
            .frame(width: 70)
            .help("Target language: \(settings.targetLanguage)")
            .accessibilityLabel("Target language")
            iconButton("AI Chat", symbol: "bubble.left.and.text.bubble.right", action: openChat)
            iconButton("Settings", symbol: "gearshape", action: openSettings)
            iconButton("Close", symbol: "xmark", action: close)
        }
        .padding(.horizontal, 7)
        .frame(width: Self.size.width, height: Self.size.height)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
    }

    private func iconButton(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .frame(width: 32, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(title)
        .accessibilityLabel(title)
    }

    static func frame(for selection: CGRect, visibleFrame: CGRect) -> CGRect {
        let rect = FloatingPanel.appKitFrame(for: selection)
        let gap: CGFloat = 8
        let x = rect.maxX - size.width
        let below = CGRect(origin: CGPoint(x: x, y: rect.minY - gap - size.height), size: size)
        let above = CGRect(origin: CGPoint(x: x, y: rect.maxY + gap), size: size)
        let candidate: CGRect
        if below.minY >= visibleFrame.minY && below.maxY <= visibleFrame.maxY {
            candidate = below
        } else if above.minY >= visibleFrame.minY && above.maxY <= visibleFrame.maxY {
            candidate = above
        } else {
            candidate = CGRect(origin: CGPoint(x: rect.maxX - gap - size.width,
                                              y: rect.minY + gap), size: size)
        }
        return FloatingPanel.clampedFrame(candidate, to: visibleFrame)
    }
}
