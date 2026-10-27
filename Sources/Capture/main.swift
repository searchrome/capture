import AppKit

// The executable entry point runs on the main thread.
MainActor.assumeIsolated {
    let application = NSApplication.shared
    let appDelegate = AppDelegate()
    application.delegate = appDelegate
    application.setActivationPolicy(.accessory)
    withExtendedLifetime(appDelegate) {
        application.run()
    }
}
