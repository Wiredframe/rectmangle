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
    private var problems: [String: String] = [:] // action name → why its shortcut is not active
    private var shownProblems: [String] = []
    private var settings: SettingsWindow?
    private var recording = false
    private var loadError: String? // set while the file cannot be read, saving would overwrite hand edits

    func applicationDidFinishLaunching(_ notification: Notification) {
        AXPermission.ensureTrusted(prompt: true)
        NSApp.mainMenu = mainMenu()
        reload()
        directoryWatcher = watch(Config.url.deletingLastPathComponent(), events: .write)
        watchFile()
    }

    /// Launching the app again while it runs (Finder, `open -a Rectmangle`) opens the settings
    /// and brings back a hidden menu bar icon.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !config.menuBarIcon { change { $0.menuBarIcon = true } }
        showSettings()
        return false
    }

    /// `open -g rectmangle://leftHalf` runs an action, for scripts and launchers. `rectmangle://settings` opens the settings,
    /// `rectmangle://settings/general` its second tab.
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls where url.scheme == "rectmangle" {
            if url.host == "settings" {
                showSettings(tab: url.path == "/general" ? 1 : nil)
            } else if let name = url.host, let action = Action(rawValue: name) {
                windows.perform(action)
            } else {
                NSSound.beep()
            }
        }
    }

    // MARK: Config

    private func reload() {
        do {
            let config = try Config.load()
            loadError = nil
            apply(config)
        } catch {
            loadError = error.localizedDescription
            showAlert(String(localized: "Could not read \(Config.url.path)"), error.localizedDescription)
        }
    }

    private func apply(_ config: Config) {
        self.config = config
        windows.config = config
        registerHotKeys()
        if recording { hotKeys.unregisterAll() } // a reload while the settings record a shortcut
        updateStatusItem(visible: config.menuBarIcon)
        updateLoginItem(enabled: config.launchAtLogin)
        settings?.update(config: config, problems: problems)

        // Saving the file triggers a reload with the same result, which must not alert twice.
        let list = problems.sorted { $0.key < $1.key }.map { "\($0.key): \($0.value)" }
        guard list != shownProblems else { return }
        shownProblems = list
        if !list.isEmpty, settings?.isVisible != true {
            showAlert(String(localized: "Some shortcuts are not active"), list.joined(separator: "\n"))
        }
    }

    private func registerHotKeys() {
        hotKeys.unregisterAll()
        active = [:]
        problems = [:]
        var used: [String: String] = [:] // "keyCode/modifiers" → action
        let layout = Shortcut.layoutMap()
        let characters = Shortcut.characterMap()

        for (name, text) in config.shortcuts.sorted(by: { $0.key < $1.key }) {
            guard let action = Action(rawValue: name) else {
                problems[name] = String(localized: "Unknown action")
                continue
            }
            if text.trimmingCharacters(in: .whitespaces).isEmpty { continue }
            do {
                let shortcut = try Shortcut(parsing: text, layout: layout)
                let key = "\(shortcut.keyCode)/\(shortcut.modifiers)"
                let display = shortcut.displayText(characters: characters)
                if let other = used[key] {
                    let title = Action(rawValue: other)?.title ?? other
                    problems[name] = String(localized: "\(display) is already used for \(title)")
                } else if hotKeys.register(shortcut, handler: { [weak self] in self?.windows.perform(action) }) {
                    used[key] = name
                    active[action] = shortcut
                } else {
                    problems[name] = String(localized: "\(display) is already taken by another app")
                }
            } catch {
                problems[name] = error.localizedDescription
            }
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

    @objc private func showSettingsFromMenu() {
        showSettings()
    }

    private func showSettings(tab: Int? = nil) {
        if settings == nil {
            let settings = SettingsWindow()
            settings.onChange = { [weak self] config in self?.save(config) }
            settings.onOpenFile = { [weak self] in self?.openConfig() }
            // Registered hotkeys would catch the keys before the recorder sees them.
            settings.onRecording = { [weak self] recording in
                self?.recording = recording
                if recording { self?.hotKeys.unregisterAll() } else { self?.registerHotKeys() }
            }
            self.settings = settings
        }
        settings?.update(config: config, problems: problems)
        settings?.show(tab: tab)
    }

    @objc private func grantAccess() {
        AXPermission.ensureTrusted(prompt: true)
    }

    @objc private func performFromMenu(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? String, let action = Action(rawValue: name) else { return }
        windows.perform(action)
    }

    @objc private func toggleLogin() {
        change { $0.launchAtLogin.toggle() }
    }

    @objc private func hideStatusItem() {
        change { $0.menuBarIcon = false }
    }

    private func change(_ edit: (inout Config) -> Void) {
        var config = self.config
        edit(&config)
        save(config)
    }

    /// The config file stays the single source of truth: the menu and the settings window write it.
    /// The change applies at once, the file watcher's reload that follows finds nothing new.
    private func save(_ config: Config) {
        if let loadError {
            showAlert(String(localized: "Could not read \(Config.url.path)"), loadError)
            return
        }
        do {
            try Config.save(config)
            apply(config)
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
        let characters = Shortcut.characterMap()
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
        menu.addItem(withTitle: String(localized: "Settings…"), action: #selector(showSettingsFromMenu), keyEquivalent: ",")
            .target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: String(localized: "Quit Rectmangle"), action: #selector(NSApplication.terminate(_:)),
                     keyEquivalent: "q")
    }

    /// Not visible for a menu bar app, but it gives the settings window ⌘W and ⌘Q.
    private func mainMenu() -> NSMenu {
        let main = NSMenu()
        let app = NSMenu()
        app.addItem(withTitle: String(localized: "Settings…"), action: #selector(showSettingsFromMenu), keyEquivalent: ",")
            .target = self
        app.addItem(withTitle: String(localized: "Close Window"), action: #selector(NSWindow.performClose(_:)),
                    keyEquivalent: "w")
        app.addItem(withTitle: String(localized: "Quit Rectmangle"), action: #selector(NSApplication.terminate(_:)),
                    keyEquivalent: "q")
        main.addItem(withTitle: "Rectmangle", action: nil, keyEquivalent: "").submenu = app
        return main
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
