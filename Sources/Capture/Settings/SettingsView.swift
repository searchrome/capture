import AppKit
import ApplicationServices
import Carbon
import ServiceManagement
import SwiftUI

@MainActor
struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject private var catalog = ModelCatalog.shared
    @State private var apiKey = ""
    @State private var keyLoaded = false
    @State private var savedKey = ""
    @State private var keySaveTask: Task<Void, Never>?
    @State private var keyStatus = ""
    @State private var testingKey = false
    @State private var catalogStatus = ""
    @State private var loadingModels = false
    @State private var visionSearch = ""
    @State private var chatSearch = ""
    @State private var recording = false
    @State private var recordingDocument = false
    @State private var keyMonitor: Any?
    @State private var screenAccess = false
    @State private var accessibilityAccess = false
    @State private var loginEnabled = false
    @State private var loginError = ""

    var body: some View {
        Form {
            Section("Keyboard shortcuts") {
                HStack {
                    Text("Capture area")
                    Spacer()
                    Text(settings.hotkey.displayString)
                    Button(recording && !recordingDocument ? "Cancel" : "Record") {
                        if recording { stopRecording() } else { startRecording() }
                    }
                    Button("Reset") { stopRecording(); settings.hotkey = .default }
                }
                HStack {
                    Text("Read document text")
                    Spacer()
                    Text(settings.documentHotkey.displayString)
                    Button(recording && recordingDocument ? "Cancel" : "Record") {
                        if recording { stopRecording() } else { startRecording(document: true) }
                    }
                    Button("Reset") { stopRecording(); settings.documentHotkey = .documentText }
                }
                if recording { Text("Press a key with a modifier…").foregroundStyle(.secondary) }
                if let error = settings.hotkeyError { Text(error).foregroundStyle(.red) }
                Text("Document text requires Accessibility access. Capture area requires Screen Recording access.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("OpenRouter") {
                HStack {
                    SecureField("API key", text: $apiKey)
                        .onSubmit { saveKey() }
                    Button(testingKey ? "Testing…" : "Test") { testKey() }
                        .disabled(testingKey)
                }
                if !keyStatus.isEmpty { Text(keyStatus).foregroundStyle(.secondary).textSelection(.enabled) }
                modelPicker("Vision model (OCR/translate)", selection: $settings.visionModel, search: $visionSearch)
                modelPicker("Chat model", selection: $settings.chatModel, search: $chatSearch)
                HStack {
                    Button(loadingModels ? "Refreshing…" : "Refresh") { loadModels(refresh: true) }
                        .disabled(loadingModels)
                    if !catalogStatus.isEmpty { Text(catalogStatus).foregroundStyle(.secondary) }
                }
                Toggle("Disable reasoning for OCR/translate", isOn: $settings.disableReasoning)
            }
            Section("Text and translation") {
                Picker("Target language", selection: $settings.targetLanguage) {
                    ForEach(AppSettings.languages, id: \.self) { Text($0).tag($0) }
                }
                Picker("Image → Text engine", selection: $settings.ocrEngine) {
                    Text("LLM (OpenRouter)").tag(AppSettings.OCREngine.llm)
                    Text("On-device (Apple Vision)").tag(AppSettings.OCREngine.onDevice)
                }
                Picker("Show translation", selection: $settings.translationDisplay) {
                    Text("Over the selection").tag(AppSettings.TranslationDisplay.overlay)
                    Text("In a panel").tag(AppSettings.TranslationDisplay.panel)
                }
                Toggle("Auto-copy result", isOn: $settings.autoCopy)
                Stepper("Max image side: \(settings.maxImageSide) px", value: $settings.maxImageSide,
                        in: 768...4096, step: 128)
            }
            Section("Agent") {
                Toggle("Ask before acting", isOn: $settings.askBeforeActing)
                permissionRow("Screen Recording", granted: screenAccess,
                              url: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")
                permissionRow("Accessibility", granted: accessibilityAccess,
                              url: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
            }
            Section("General") {
                Toggle("Launch at login", isOn: Binding(get: { loginEnabled }, set: { setLaunchAtLogin($0) }))
                if !loginError.isEmpty { Text(loginError).foregroundStyle(.red) }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            do { apiKey = try Keychain.read() ?? ""; savedKey = apiKey; keyLoaded = true }
            catch { keyStatus = error.localizedDescription }
            updateStatus()
            loadModels()
        }
        .onDisappear { stopRecording(); saveKey() }
        .onChange(of: apiKey) { _, _ in
            guard keyLoaded else { return }
            keySaveTask?.cancel()
            keySaveTask = Task { @MainActor in
                do { try await Task.sleep(nanoseconds: 500_000_000) }
                catch { return }
                saveKey()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in updateStatus() }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.willCloseNotification)) { notification in
            if (notification.object as? NSWindow)?.contentView is NSHostingView<SettingsView> { stopRecording(); saveKey() }
        }
    }

    private func modelPicker(_ title: String, selection: Binding<String>, search: Binding<String>) -> some View {
        let filtered = catalog.models.filter {
            search.wrappedValue.isEmpty || $0.name.localizedCaseInsensitiveContains(search.wrappedValue)
                || $0.id.localizedCaseInsensitiveContains(search.wrappedValue)
        }
        return VStack(alignment: .leading, spacing: 4) {
            Text(title)
            TextField("Search models", text: search)
            Picker(title, selection: selection) {
                if !filtered.contains(where: { $0.id == selection.wrappedValue }) {
                    Text(selection.wrappedValue.isEmpty ? "Select a model" : selection.wrappedValue).tag(selection.wrappedValue)
                }
                ForEach(filtered) { model in
                    Text("\(model.name) — \(model.priceDescription)").tag(model.id)
                }
            }
            .labelsHidden()
            TextField("Model ID", text: selection)
        }
    }

    private func permissionRow(_ title: String, granted: Bool, url: String) -> some View {
        HStack {
            Text("\(title): \(granted ? "Granted" : "Not granted")")
            Spacer()
            Button("Open System Settings") { if let url = URL(string: url) { NSWorkspace.shared.open(url) } }
        }
    }

    private func loadModels(refresh: Bool = false) {
        guard !loadingModels else { return }
        loadingModels = true
        catalogStatus = ""
        Task {
            do { try await catalog.load(refresh: refresh) }
            catch { catalogStatus = error.localizedDescription }
            loadingModels = false
        }
    }

    private func saveKey() {
        keySaveTask?.cancel()
        keySaveTask = nil
        guard keyLoaded, apiKey != savedKey else { return }
        do {
            if apiKey.isEmpty { try Keychain.delete() } else { try Keychain.save(apiKey) }
            savedKey = apiKey
            keyStatus = ""
        } catch { keyStatus = error.localizedDescription }
    }

    private func testKey() {
        saveKey()
        guard apiKey == savedKey else { return }
        testingKey = true
        keyStatus = ""
        Task {
            do { keyStatus = try await OpenRouterClient().testKey() }
            catch { keyStatus = error.localizedDescription }
            testingKey = false
        }
    }

    private func startRecording(document: Bool = false) {
        guard keyMonitor == nil else { return }
        recording = true
        recordingDocument = document
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            var modifiers: UInt32 = 0
            if flags.contains(.command) { modifiers |= UInt32(cmdKey) }
            if flags.contains(.shift) { modifiers |= UInt32(shiftKey) }
            if flags.contains(.option) { modifiers |= UInt32(optionKey) }
            if flags.contains(.control) { modifiers |= UInt32(controlKey) }
            guard modifiers != 0 else { return nil }
            let hotkey = Hotkey(keyCode: UInt32(event.keyCode), modifiers: modifiers)
            guard hotkey != (document ? settings.hotkey : settings.documentHotkey) else { NSSound.beep(); return nil }
            if document { settings.documentHotkey = hotkey } else { settings.hotkey = hotkey }
            stopRecording()
            return nil
        }
    }

    private func stopRecording() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
        recording = false
    }

    private func updateStatus() {
        screenAccess = CGPreflightScreenCaptureAccess()
        accessibilityAccess = AXIsProcessTrusted()
        loginEnabled = SMAppService.mainApp.status == .enabled
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
            loginError = ""
        } catch { loginError = error.localizedDescription }
        loginEnabled = SMAppService.mainApp.status == .enabled
        if enabled && !loginEnabled && loginError.isEmpty {
            loginError = "Enable Capture in System Settings → General → Login Items."
        }
    }
}
