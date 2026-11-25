// Coward Dock — keeps the Dock visible, auto-hides it only while a window overlaps it.
import AppKit
import ServiceManagement

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let watcher = DockWatcher()
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let stateItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let enabledItem = NSMenuItem(title: "Enabled", action: #selector(toggleEnabled), keyEquivalent: "e")
    private let loginItem = NSMenuItem(title: "Launch at Login", action: #selector(toggleLogin), keyEquivalent: "")
    private let accessItem = NSMenuItem(title: "Allow Window Resizing…", action: #selector(askAccessibility), keyEquivalent: "")
    private var signalSources: [DispatchSourceSignal] = []

    private var enabled: Bool {
        get { UserDefaults.standard.object(forKey: "enabled") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "enabled") }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let menu = NSMenu()
        menu.delegate = self
        stateItem.isEnabled = false
        let about = NSMenuItem(title: "About Coward Dock", action: #selector(showAbout), keyEquivalent: "")
        let quit = NSMenuItem(title: "Quit Coward Dock", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        accessItem.toolTip = "Lets Coward Dock stretch windows into the space the hidden Dock leaves (Accessibility permission)."
        for item in [stateItem, enabledItem, loginItem, accessItem, about] { item.target = self }
        for item in [stateItem, .separator(), enabledItem, loginItem, accessItem, .separator(), about, quit] { menu.addItem(item) }
        statusItem.menu = menu

        if !AXIsProcessTrusted(), !UserDefaults.standard.bool(forKey: "askedAccessibility") {
            UserDefaults.standard.set(true, forKey: "askedAccessibility")  // ask once; the menu item stays for later
            askAccessibility()
        }

        for sig in [SIGINT, SIGTERM] {  // `kill`/`killall` still leave the Dock visible
            signal(sig, SIG_IGN)
            let s = DispatchSource.makeSignalSource(signal: sig, queue: .main)
            s.setEventHandler { NSApp.terminate(nil) }
            s.resume()
            signalSources.append(s)
        }

        watcher.onChange = { [weak self] in self?.refresh() }
        if enabled { watcher.start() }
        refresh()
    }

    func applicationWillTerminate(_ notification: Notification) { watcher.stop() }

    func menuWillOpen(_ menu: NSMenu) { refresh() }

    private func refresh() {
        let on = watcher.running
        enabledItem.state = on ? .on : .off
        loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
        accessItem.isHidden = AXIsProcessTrusted()
        stateItem.title = !on ? "Paused" : watcher.hidden ? "Dock hidden: a window overlaps it" : "Dock visible"
        let symbol = on && watcher.hidden ? "dock.arrow.down.rectangle" : "dock.rectangle"
        statusItem.button?.image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Coward Dock")
        statusItem.button?.appearsDisabled = !on
    }

    @objc private func toggleEnabled() {
        enabled.toggle()
        if enabled { watcher.start() } else { watcher.stop() }
        refresh()
    }

    @objc private func toggleLogin() {
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled { try service.unregister() } else { try service.register() }
            if service.status == .requiresApproval { SMAppService.openSystemSettingsLoginItems() }
        } catch {
            NSApp.activate()
            NSAlert(error: error).runModal()
        }
        refresh()
    }

    @objc private func askAccessibility() {
        // Shows the system prompt, which links to System Settings → Privacy & Security → Accessibility.
        AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary)
    }

    @objc private func showAbout() {
        NSApp.activate()
        NSApp.orderFrontStandardAboutPanel(nil)
    }
}

MainActor.assumeIsolated {
    let delegate = AppDelegate()
    NSApplication.shared.delegate = delegate
    NSApplication.shared.run()
}
