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
    private var alertShown = false
    private var config = Config()
    private var active: [Action: Shortcut] = [:]

    func applicationDidFinishLaunching(_ notification: Notification) {
        AXPermission.ensureTrusted(prompt: true)
        reload()
        directoryWatcher = watch(Config.url.deletingLastPathComponent(), events: .write)
        watchFile()
    }

    /// Launching the app again while it runs (Finder, `open -a Rectmangle`) brings back a hidden menu bar icon,
    /// otherwise it opens the config.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if config.menuBarIcon { openConfig() } else { setConfig("menuBarIcon", to: true) }
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
            showAlert(String(localized: "Could not read \(Config.url.path)"), error.localizedDescription)
            return
        }

        self.config = config
        windows.config = config
        hotKeys.unregisterAll()
        active = [:]
        var problems: [String] = []
        var used: [String: String] = [:] // "keyCode/modifiers" → action
        let layout = Shortcut.layoutMap()

        for (name, text) in config.shortcuts.sorted(by: { $0.key < $1.key }) {
            guard let action = Action(rawValue: name) else {
                problems.append("Unknown action \"\(name)\"")
                continue
            }
            if text.trimmingCharacters(in: .whitespaces).isEmpty { continue }
            do {
                let shortcut = try Shortcut(parsing: text, layout: layout)
                let key = "\(shortcut.keyCode)/\(shortcut.modifiers)"
                if let other = used[key] {
                    problems.append("\(name): \(text) is already used for \(other)")
                } else if hotKeys.register(shortcut, handler: { [weak self] in self?.windows.perform(action) }) {
                    used[key] = name
                    active[action] = shortcut
                } else {
                    problems.append("\(name): \(text) is already taken by another app")
                }
            } catch {
                problems.append("\(name): \(error.localizedDescription)")
            }
        }

        updateStatusItem(visible: config.menuBarIcon)
        updateLoginItem(enabled: config.launchAtLogin)

        if !problems.isEmpty {
            showAlert(String(localized: "Some shortcuts are not active"), problems.joined(separator: "\n"))
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

    @objc private func performFromMenu(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? String, let action = Action(rawValue: name) else { return }
        windows.perform(action)
    }

    @objc private func toggleLogin() {
        setConfig("launchAtLogin", to: !config.launchAtLogin)
    }

    @objc private func hideStatusItem() {
        setConfig("menuBarIcon", to: false)
    }

    /// The config stays the single source of truth: menu toggles write it, the file watcher applies the change.
    private func setConfig(_ key: String, to value: Bool) {
        do {
            try Config.set(key, to: value)
        } catch {
            showAlert(String(localized: "Could not write \(Config.url.path)"), error.localizedDescription)
        }
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

    /// Built on every open, so shortcuts and the access item always match the current state.
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        if !AXIsProcessTrusted() {
            menu.addItem(withTitle: String(localized: "Grant Accessibility Access…"), action: #selector(grantAccess),
                         keyEquivalent: "").target = self
            menu.addItem(.separator())
        }

        // The status menu does not activate Rectmangle, so the frontmost window is still the one to arrange.
        var characters: [UInt32: String] = [:]
        for (character, code) in Shortcut.layoutMap() where characters[code] == nil { characters[code] = character }
        for group in Action.menuGroups {
            for action in group {
                let item = menu.addItem(withTitle: action.title, action: #selector(performFromMenu(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = action.rawValue
                if let key = active[action]?.menuKey(characters: characters) {
                    item.keyEquivalent = key.key
                    item.keyEquivalentModifierMask = key.modifiers
                }
            }
            menu.addItem(.separator())
        }

        let login = menu.addItem(withTitle: String(localized: "Launch at Login"), action: #selector(toggleLogin),
                                 keyEquivalent: "")
        login.target = self
        login.state = config.launchAtLogin ? .on : .off
        let hide = menu.addItem(withTitle: String(localized: "Hide Menu Bar Icon"), action: #selector(hideStatusItem),
                                keyEquivalent: "")
        hide.target = self
        hide.toolTip = String(localized: "Launch Rectmangle again from the Finder to bring it back.")
        menu.addItem(withTitle: String(localized: "Edit Config…"), action: #selector(openConfig), keyEquivalent: "")
            .target = self
        menu.addItem(withTitle: String(localized: "Reload Config"), action: #selector(reloadFromMenu), keyEquivalent: "")
            .target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: String(localized: "Quit Rectmangle"), action: #selector(NSApplication.terminate(_:)),
                     keyEquivalent: "q")
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

    /// One alert at a time: saving the config again while an alert is open must not stack them.
    private func showAlert(_ title: String, _ message: String) {
        guard !alertShown else { return }
        alertShown = true
        defer { alertShown = false }
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.runModal()
    }
}

extension Action {
    static let menuGroups: [[Action]] = [
        [.leftHalf, .rightHalf, .centerHalf, .topHalf, .bottomHalf],
        [.topLeft, .topRight, .bottomLeft, .bottomRight],
        [.firstThird, .centerThird, .lastThird, .firstTwoThirds, .lastTwoThirds],
        [.maximize, .almostMaximize, .maximizeHeight, .larger, .smaller, .center, .restore],
        [.nextDisplay, .previousDisplay],
    ]

    var title: String {
        switch self {
        case .leftHalf: String(localized: "Left Half")
        case .rightHalf: String(localized: "Right Half")
        case .centerHalf: String(localized: "Center Half")
        case .topHalf: String(localized: "Top Half")
        case .bottomHalf: String(localized: "Bottom Half")
        case .topLeft: String(localized: "Top Left")
        case .topRight: String(localized: "Top Right")
        case .bottomLeft: String(localized: "Bottom Left")
        case .bottomRight: String(localized: "Bottom Right")
        case .firstThird: String(localized: "First Third")
        case .centerThird: String(localized: "Center Third")
        case .lastThird: String(localized: "Last Third")
        case .firstTwoThirds: String(localized: "First Two Thirds")
        case .lastTwoThirds: String(localized: "Last Two Thirds")
        case .maximize: String(localized: "Maximize")
        case .almostMaximize: String(localized: "Almost Maximize")
        case .maximizeHeight: String(localized: "Maximize Height")
        case .larger: String(localized: "Larger")
        case .smaller: String(localized: "Smaller")
        case .center: String(localized: "Center")
        case .restore: String(localized: "Restore")
        case .nextDisplay: String(localized: "Next Display")
        case .previousDisplay: String(localized: "Previous Display")
        }
    }
}

enum AXPermission {
    static func ensureTrusted(prompt: Bool) {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: prompt] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }
}
