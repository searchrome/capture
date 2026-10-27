#if DEBUG
import AppKit

@MainActor
enum DebugSnapshots {
    private static func argument(_ name: String) -> String? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: name), arguments.indices.contains(index + 1) else { return nil }
        return arguments[index + 1]
    }

    private static var directory: URL? {
        guard let path = argument("-debugSnapshotDir"), !path.isEmpty else { return nil }
        return URL(fileURLWithPath: (path as NSString).expandingTildeInPath, isDirectory: true)
    }

    static func scheduleQuit() {
        guard let value = argument("-debugQuitAfter"), let seconds = Double(value),
              seconds.isFinite, seconds >= 0 else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { NSApp.terminate(nil) }
    }

    static func write(name: String) {
        guard let directory else { return }
        do {
            let files = FileManager.default
            try files.createDirectory(at: directory, withIntermediateDirectories: true)
            var entries: [[String: Any]] = []
            var usedNames: Set<String> = []
            let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
            for window in NSApp.windows where window.isVisible {
                let kind = kind(of: window)
                let frame = window.frame
                let title = window.title
                entries.append([
                    "kind": kind, "title": title,
                    "frame": ["x": frame.minX, "y": primaryHeight - frame.maxY,
                              "width": frame.width, "height": frame.height]
                ])
                guard let view = window.contentView, !view.bounds.isEmpty else { continue }
                view.layoutSubtreeIfNeeded()
                view.displayIfNeeded()
                guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { continue }
                view.cacheDisplay(in: view.bounds, to: bitmap)
                guard let png = bitmap.representation(using: .png, properties: [:]) else { continue }
                let label = (title.isEmpty ? kind : title).map { character in
                    character == "/" || character == ":" || character.isNewline ? "_" : character
                }
                let base = String(label)
                var suffix = base
                var count = 2
                while usedNames.contains(suffix) {
                    suffix = "\(base)-\(count)"
                    count += 1
                }
                usedNames.insert(suffix)
                try png.write(to: directory.appendingPathComponent("\(name)-\(suffix).png"), options: .atomic)
            }
            let data = try JSONSerialization.data(withJSONObject: entries, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: directory.appendingPathComponent("\(name)-windows.json"), options: .atomic)
        } catch {
            NSLog("Debug snapshots: %@", error.localizedDescription)
        }
    }

    static func writeText(_ text: String, file: String, append: Bool = false) {
        guard let directory else { return }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let url = directory.appendingPathComponent(file)
            let data = Data(text.utf8)
            if append && FileManager.default.fileExists(atPath: url.path) {
                let handle = try FileHandle(forWritingTo: url)
                defer { try? handle.close() }
                try handle.seekToEnd()
                try handle.write(contentsOf: data)
            } else {
                try data.write(to: url, options: .atomic)
            }
        } catch {
            NSLog("Debug snapshots: %@", error.localizedDescription)
        }
    }

    private static func kind(of window: NSWindow) -> String {
        if window is SelectionHighlight { return "highlight" }
        if window.identifier?.rawValue == "debugActionBar" { return "action-bar" }
        if window.identifier?.rawValue == "debugTranslationOverlay" { return "translation-overlay" }
        if window.identifier?.rawValue == "debugTranslationPill" { return "translation-pill" }
        switch window.title {
        case "Capture Result": return "result"
        case "Capture Chat": return "chat"
        case "Capture Settings": return "settings"
        default: return String(describing: type(of: window))
        }
    }
}
#endif
