import AppKit
import SwiftUI

@MainActor
final class SelectionHighlight: FloatingPanel {
    init(selection: CGRect) {
        // Two points outside the selection, with one extra point for antialiasing.
        let frame = FloatingPanel.appKitFrame(for: selection).insetBy(dx: -3, dy: -3)
        super.init(frame: frame, content:
            RoundedRectangle(cornerRadius: 5)
                .strokeBorder(Color.accentColor, lineWidth: 2)
                .padding(1)
        )
        ignoresMouseEvents = true
        hasShadow = false
    }
}
