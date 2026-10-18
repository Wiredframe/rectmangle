import AppKit
import ServiceManagement

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let hotKeys = HotKeyCenter()
    private let windows = WindowManager()
    private var statusItem: NSStatusItem?
    private var directoryWatcher: DispatchSourceFileSystemObject?
    private var fileWatcher: DispatchSourceFileSystemObject?
    private var reloadPending = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        AXPermission.ensureTrusted(prompt: true)
        reload()
        directoryWatcher = watch(Config.url.deletingLastPathComponent(), events: .write)
        watchFile()
    }

    /// Launching the app again while it runs opens the config, so it stays reachable without a menu bar icon.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        openConfig()
        return false
    }

    /// `open -g rectmangle://leftHalf` runs an action, for scripts and launchers.
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls where url.scheme == "rectmangle" {
            if let name = url.host, let action = Action(rawValue: name) {
                windows.perform(action)
            } else {
                NSSound.beep()
            }
        }
    }

    // MARK: Config

    private func reload() {
        let config: Config
        do {
            config = try Config.load()
        } catch {
            showAlert("\(Config.url.path) ließ sich nicht lesen", error.localizedDescription)
            return
        }

        windows.config = config
        hotKeys.unregisterAll()
        var problems: [String] = []
        var used: [String: String] = [:] // "keyCode/modifiers" → action
        let layout = Shortcut.layoutMap()

        for (name, text) in config.shortcuts.sorted(by: { $0.key < $1.key }) {
            guard let action = Action(rawValue: name) else {
                problems.append("Unbekannte Aktion „\(name)“")
                continue
            }
            if text.trimmingCharacters(in: .whitespaces).isEmpty { continue }
            do {
                let shortcut = try Shortcut(parsing: text, layout: layout)
                let key = "\(shortcut.keyCode)/\(shortcut.modifiers)"
                if let other = used[key] {
                    problems.append("\(name): \(text) ist schon für \(other) vergeben")
                } else if hotKeys.register(shortcut, handler: { [weak self] in self?.windows.perform(action) }) {
                    used[key] = name
                } else {
                    problems.append("\(name): \(text) ist schon von einer anderen App belegt")
                }
            } catch {
                problems.append("\(name): \(error.localizedDescription)")
            }
        }

        updateStatusItem(visible: config.menuBarIcon)
        updateLoginItem(enabled: config.launchAtLogin)

        if !problems.isEmpty {
            showAlert("Einige Kurzbefehle sind nicht aktiv", problems.joined(separator: "\n"))
        }
    }

    /// The directory catches editors that replace the file, the file itself catches editors that write into it.
    private func watch(_ url: URL, events: DispatchSource.FileSystemEvent) -> DispatchSourceFileSystemObject? {
        let fd = open(url.path, O_EVTONLY)
        guard fd >= 0 else { return nil }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: events, queue: .main)
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.scheduleReload() }
        }
        source.setCancelHandler { close(fd) }
        source.resume()
        return source
    }

    /// A replaced file is a new inode, so the file watcher is renewed on every reload.
    private func watchFile() {
        fileWatcher?.cancel()
        fileWatcher = watch(Config.url, events: [.write, .delete, .rename])
    }

    private func scheduleReload() {
        guard !reloadPending else { return }
        reloadPending = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.reloadPending = false
                self.watchFile()
                self.reload()
            }
        }
    }

    @objc private func openConfig() {
        NSWorkspace.shared.open(Config.url)
    }

    @objc private func reloadFromMenu() {
        reload()
    }

    @objc private func grantAccess() {
        AXPermission.ensureTrusted(prompt: true)
    }

    // MARK: Menu bar and login item

    private func updateStatusItem(visible: Bool) {
        guard visible else {
            if let statusItem { NSStatusBar.system.removeStatusItem(statusItem) }
            statusItem = nil
            return
        }
        guard statusItem == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "rectangle.split.2x1", accessibilityDescription: "Rectmangle")
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        statusItem = item
    }

    /// Built on every open, so the access item disappears once access is granted.
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        if !AXIsProcessTrusted() {
            menu.addItem(withTitle: "Bedienungshilfen freigeben …", action: #selector(grantAccess), keyEquivalent: "").target = self
            menu.addItem(.separator())
        }
        menu.addItem(withTitle: "Konfiguration bearbeiten …", action: #selector(openConfig), keyEquivalent: ",").target = self
        menu.addItem(withTitle: "Konfiguration neu laden", action: #selector(reloadFromMenu), keyEquivalent: "r").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Rectmangle beenden", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    }

    private func updateLoginItem(enabled: Bool) {
        let service = SMAppService.mainApp
        do {
            if enabled, service.status != .enabled {
                try service.register()
            } else if !enabled, service.status == .enabled {
                try service.unregister()
            }
        } catch {
            NSLog("Rectmangle: login item: \(error.localizedDescription)")
        }
    }

    private func showAlert(_ title: String, _ message: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.runModal()
    }
}

enum AXPermission {
    static func ensureTrusted(prompt: Bool) {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: prompt] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }
}
