import AppKit
import ApplicationServices
import PDFKit

/// Reads only the focused window of the app captured when the command was invoked.
struct DocumentTextReader {
    struct Output {
        let text: String
        let isPartial: Bool
    }

    struct ReadError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    func read(pid: pid_t) throws -> Output {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.3)
        guard let window = element(app, kAXFocusedWindowAttribute) else {
            throw ReadError(message: "The app does not expose an active window. Try Image → Text instead.")
        }
        // Only local files: reading a browser document never triggers a network download.
        if let path = attribute(window, kAXDocumentAttribute) as? String,
           let url = URL(string: path), url.isFileURL, url.pathExtension.lowercased() == "pdf",
           let pdf = PDFDocument(url: url) {
            guard let text = pdf.string, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw ReadError(message: "This PDF has no readable text layer. Image recognition is needed. Choose Capture an area… then Image → Text.")
            }
            return Output(text: text, isPartial: false)
        }

        var foundDocument = false
        var visited = Set<AXUIElement>()
        var nodes = 0
        var truncated = false
        let deadline = Date().addingTimeInterval(12)
        func walk(_ node: AXUIElement, depth: Int, documentOnly: Bool) throws -> [String] {
            try Task.checkCancellation()
            guard depth < 80, nodes < 15_000, Date() < deadline else {
                truncated = true
                return []
            }
            guard visited.insert(node).inserted else { return [] }
            nodes += 1
            let role = attribute(node, kAXRoleAttribute) as? String ?? ""
            let subrole = attribute(node, kAXSubroleAttribute) as? String ?? ""
            guard subrole != "AXSecureTextField" else { return [] }
            let isDocument = role == "AXWebArea" || role == "AXTextArea"
            if isDocument { foundDocument = true }
            if !documentOnly || isDocument {
                if ["AXStaticText", "AXTextArea", "AXTextField"].contains(role),
                   let value = attribute(node, kAXValueAttribute) as? String,
                   !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    return [value]
                }
            }
            let children = attribute(node, kAXChildrenAttribute) as? [AXUIElement] ?? []
            var lines: [String] = []
            for child in children {
                lines += try walk(child, depth: depth + 1, documentOnly: documentOnly && !isDocument)
                if truncated { break }
            }
            return lines
        }
        var lines = try walk(window, depth: 0, documentOnly: true)
        if lines.isEmpty && !truncated && !foundDocument {
            visited.removeAll()
            lines = try walk(window, depth: 0, documentOnly: false)
        }
        guard !lines.isEmpty else {
            throw ReadError(message: "No readable text was exposed by this window. Try Image → Text for scanned PDFs, images, or unsupported apps.")
        }
        return Output(text: lines.joined(separator: "\n"),
                      isPartial: truncated)
    }

    private func attribute(_ node: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(node, name as CFString, &value) == .success else { return nil }
        return value
    }

    private func element(_ node: AXUIElement, _ name: String) -> AXUIElement? {
        guard let value = attribute(node, name), CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }
}
