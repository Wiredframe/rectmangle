import AppKit

/// The settings window: shortcuts recorded per action, plus the other options. It edits a copy of the config
/// and hands every change to `onChange`, which saves the file. The file stays the single source of truth.
@MainActor
final class SettingsWindow: NSWindowController, NSWindowDelegate {
    var onChange: ((Config) -> Void)?
    var onRecording: ((Bool) -> Void)?
    var onOpenFile: (() -> Void)?

    private var config = Config()
    private var problems: [String: String] = [:]
    private var characters: [UInt32: String] = [:]
    private var fields: [Action: ShortcutField] = [:]
    private var warnings: [Action: NSImageView] = [:]
    private let status = NSTextField(wrappingLabelWithString: "")

    private let launchAtLogin = NSButton(checkboxWithTitle: String(localized: "Launch at login"), target: nil, action: nil)
    private let menuBarIcon = NSButton(checkboxWithTitle: String(localized: "Show icon in the menu bar"), target: nil, action: nil)
    private let halvesAcross = NSButton(
        checkboxWithTitle: String(localized: "Repeating Left or Right Half moves the window to the next display"),
        target: nil, action: nil)
    private let moveCursor = NSButton(
        checkboxWithTitle: String(localized: "Move the mouse pointer along to the other display"), target: nil, action: nil)
    private let almostWidth = NSSlider(value: 90, minValue: 50, maxValue: 100, target: nil, action: nil)
    private let almostHeight = NSSlider(value: 90, minValue: 50, maxValue: 100, target: nil, action: nil)
    private let sizeStep = NSSlider(value: 30, minValue: 10, maxValue: 200, target: nil, action: nil)
    private let almostWidthValue = NSTextField(labelWithString: "")
    private let almostHeightValue = NSTextField(labelWithString: "")
    private let sizeStepValue = NSTextField(labelWithString: "")
    private var sliderSave: DispatchWorkItem?

    init() {
        super.init(window: nil)
        // The tabs come first: the window takes its size from the selected tab when it is created.
        let tabs = NSTabViewController()
        tabs.tabStyle = .toolbar
        tabs.addTabViewItem(item(String(localized: "Shortcuts"), "keyboard", shortcutsView()))
        tabs.addTabViewItem(item(String(localized: "General"), "gearshape", generalView()))
        let window = NSWindow(contentViewController: tabs)
        window.styleMask = [.titled, .closable]
        window.toolbarStyle = .preference
        window.isReleasedWhenClosed = false
        window.delegate = self
        if let size = tabs.tabViewItems.first?.viewController?.preferredContentSize { window.setContentSize(size) }
        self.window = window
    }

    required init?(coder: NSCoder) { fatalError() }

    private func item(_ title: String, _ symbol: String, _ view: NSView) -> NSTabViewItem {
        let controller = NSViewController()
        controller.view = view
        controller.title = title
        view.layoutSubtreeIfNeeded()
        view.setFrameSize(view.fittingSize)
        controller.preferredContentSize = view.fittingSize
        let item = NSTabViewItem(viewController: controller)
        item.label = title
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
        return item
    }

    func show(tab: Int? = nil) {
        characters = Shortcut.characterMap() // the keyboard layout may have changed since
        refresh()
        let opening = window?.isVisible != true
        if let tab, let tabs = window?.contentViewController as? NSTabViewController, tabs.tabViewItems.indices.contains(tab) {
            tabs.selectedTabViewItemIndex = tab
        }
        if opening { window?.center() }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        if opening { window?.makeFirstResponder(nil) } // no focus ring on the first button
    }

    var isVisible: Bool { window?.isVisible == true }

    /// The config as loaded from the file, with the problems found while registering its shortcuts.
    func update(config: Config, problems: [String: String]) {
        guard config != self.config || problems != self.problems else { return }
        self.config = config
        self.problems = problems
        refresh()
    }

    /// A recording must not outlive the window's focus, the hotkeys are paused while it runs.
    func windowDidResignKey(_ notification: Notification) {
        window?.makeFirstResponder(nil)
    }

    func windowWillClose(_ notification: Notification) {
        window?.makeFirstResponder(nil) // stops a running recording
        flushSliders()
    }

    // MARK: Shortcuts tab

    private func shortcutsView() -> NSView {
        let left = column([[.leftHalf, .rightHalf, .centerHalf, .topHalf, .bottomHalf],
                           [.topLeft, .topRight, .bottomLeft, .bottomRight],
                           [.nextDisplay, .previousDisplay]])
        let right = column([[.firstThird, .centerThird, .lastThird, .firstTwoThirds, .lastTwoThirds],
                            [.maximize, .almostMaximize, .maximizeHeight, .larger, .smaller, .center, .restore]])
        let columns = NSStackView(views: [left, right])
        columns.alignment = .top
        columns.spacing = 32

        status.textColor = .secondaryLabelColor
        status.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        status.preferredMaxLayoutWidth = 420
        showHint()
        let restore = NSButton(title: String(localized: "Restore Defaults…"), target: self, action: #selector(restoreDefaults))
        let footer = NSStackView(views: [status, restore])
        footer.alignment = .firstBaseline
        footer.distribution = .fill
        status.setContentHuggingPriority(.defaultLow, for: .horizontal)
        restore.setContentHuggingPriority(.required, for: .horizontal)

        let stack = NSStackView(views: [columns, footer])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 20
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 24, bottom: 20, right: 24)
        footer.widthAnchor.constraint(equalTo: columns.widthAnchor).isActive = true
        return stack
    }

    private func column(_ groups: [[Action]]) -> NSView {
        let grid = NSGridView()
        grid.rowSpacing = 6
        grid.columnSpacing = 8
        for (index, group) in groups.enumerated() {
            for (position, action) in group.enumerated() {
                let icon = NSImageView(image: ActionIcon.image(for: action))
                icon.contentTintColor = .secondaryLabelColor
                icon.heightAnchor.constraint(equalToConstant: 18).isActive = true
                let field = ShortcutField()
                field.onRecording = { [weak self] recording in
                    self?.onRecording?(recording)
                    if recording { self?.showHint() }
                }
                field.onChange = { [weak self] shortcut in self?.set(shortcut, for: action) ?? false }
                fields[action] = field
                let warning = NSImageView(image: NSImage(systemSymbolName: "exclamationmark.triangle.fill",
                                                         accessibilityDescription: nil) ?? NSImage())
                warning.contentTintColor = .systemOrange
                warning.isHidden = true
                warnings[action] = warning
                let row = grid.addRow(with: [icon, NSTextField(labelWithString: action.title), field, warning])
                row.yPlacement = .center
                if index > 0, position == 0 { row.topPadding = 12 }
            }
        }
        grid.column(at: 0).xPlacement = .center
        grid.column(at: 0).width = 26
        grid.column(at: 3).width = 16
        grid.setContentHuggingPriority(.required, for: .vertical)
        return grid
    }

    /// Takes a recorded shortcut, unless another action already has it.
    private func set(_ shortcut: Shortcut?, for action: Action) -> Bool {
        if let shortcut {
            let layout = Shortcut.layoutMap()
            characters = Shortcut.characterMap()
            for other in Action.allCases where other != action {
                guard let text = config.shortcuts[other.rawValue], !text.isEmpty,
                      let existing = try? Shortcut(parsing: text, layout: layout),
                      existing.conflicts(with: shortcut) else { continue }
                NSSound.beep()
                showStatus(String(localized: "\(shortcut.displayText(characters: characters)) is already used for \(other.title)."),
                           error: true)
                return false
            }
        }
        characters = Shortcut.characterMap() // the keyboard layout may have changed while the window was open
        config.shortcuts[action.rawValue] = shortcut?.configText(characters: characters) ?? ""
        showHint()
        onChange?(config)
        return true
    }

    @objc private func restoreDefaults() {
        guard let window else { return }
        let alert = NSAlert()
        alert.messageText = String(localized: "Restore the default shortcuts?")
        alert.informativeText = String(localized: "Your own shortcuts will be replaced.")
        alert.addButton(withTitle: String(localized: "Restore"))
        alert.addButton(withTitle: String(localized: "Cancel"))
        alert.beginSheetModal(for: window) { [weak self] response in
            MainActor.assumeIsolated {
                guard let self, response == .alertFirstButtonReturn else { return }
                self.config.shortcuts = Config.defaultShortcuts
                self.refresh()
                self.onChange?(self.config)
            }
        }
    }

    private func showHint() {
        showStatus(String(localized: "Click a field and press the keys. Esc cancels, ⌫ clears."), error: false)
    }

    private func showStatus(_ text: String, error: Bool) {
        status.stringValue = text
        status.textColor = error ? .systemRed : .secondaryLabelColor
    }

    // MARK: General tab

    private func generalView() -> NSView {
        for button in [launchAtLogin, menuBarIcon, halvesAcross, moveCursor] {
            button.target = self
            button.action = #selector(toggled(_:))
        }
        for slider in [almostWidth, almostHeight, sizeStep] {
            slider.target = self
            slider.action = #selector(slid(_:))
            slider.isContinuous = true
            slider.widthAnchor.constraint(equalToConstant: 180).isActive = true
        }
        for label in [almostWidthValue, almostHeightValue, sizeStepValue] {
            label.font = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
            label.widthAnchor.constraint(equalToConstant: 50).isActive = true
        }
        menuBarIcon.toolTip = String(localized: "Launch Rectmangle again from the Finder to bring it back.")

        func slider(_ caption: String, _ slider: NSSlider, _ value: NSTextField) -> NSView {
            let label = NSTextField(labelWithString: caption)
            label.widthAnchor.constraint(equalToConstant: 56).isActive = true
            let stack = NSStackView(views: [label, slider, value])
            stack.spacing = 8
            return stack
        }
        let empty = NSGridCell.emptyContentView
        let openFile = NSButton(title: String(localized: "Open Config File"), target: self, action: #selector(openFile))
        let fileHint = NSTextField(wrappingLabelWithString: String(localized: "Changes to the file apply as soon as it is saved."))
        fileHint.textColor = .secondaryLabelColor
        fileHint.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        fileHint.preferredMaxLayoutWidth = 360

        let grid = NSGridView(views: [
            [label("Startup:"), launchAtLogin],
            [empty, menuBarIcon],
            [label("Displays:"), halvesAcross],
            [empty, moveCursor],
            [label("Almost Maximize:"), slider(String(localized: "Width"), almostWidth, almostWidthValue)],
            [empty, slider(String(localized: "Height"), almostHeight, almostHeightValue)],
            [label("Larger, Smaller:"), slider(String(localized: "Step"), sizeStep, sizeStepValue)],
            [label("Config:"), openFile],
            [empty, fileHint],
        ])
        grid.rowSpacing = 8
        grid.columnSpacing = 10
        grid.column(at: 0).xPlacement = .trailing
        grid.rowAlignment = .firstBaseline
        for index in [2, 4, 6, 7] { grid.row(at: index).topPadding = 14 }

        let container = NSView()
        grid.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(grid)
        NSLayoutConstraint.activate([
            grid.topAnchor.constraint(equalTo: container.topAnchor, constant: 20),
            grid.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -20),
            grid.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 24),
            grid.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -24),
        ])
        return container
    }

    private func label(_ key: String.LocalizationValue) -> NSTextField {
        NSTextField(labelWithString: String(localized: key))
    }

    @objc private func toggled(_ sender: NSButton) {
        let on = sender.state == .on
        switch sender {
        case launchAtLogin: config.launchAtLogin = on
        case menuBarIcon: config.menuBarIcon = on
        case halvesAcross: config.halvesAcrossDisplays = on
        case moveCursor: config.moveCursorAcrossDisplays = on
        default: return
        }
        onChange?(config)
    }

    /// Sliders update their label at once but save only once they rest, not on every pixel of a drag.
    @objc private func slid(_ sender: NSSlider) {
        readSliders()
        showSliderValues()
        sliderSave?.cancel()
        let save = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.flushSliders() }
        }
        sliderSave = save
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: save)
    }

    private func flushSliders() {
        guard let save = sliderSave else { return }
        save.cancel()
        sliderSave = nil
        readSliders() // a reload in between may have put older values into the config
        onChange?(config)
    }

    private func readSliders() {
        config.almostMaximizeWidth = almostWidth.doubleValue.rounded() / 100
        config.almostMaximizeHeight = almostHeight.doubleValue.rounded() / 100
        config.sizeStep = (sizeStep.doubleValue / 5).rounded() * 5
    }

    private func showSliderValues() {
        almostWidthValue.stringValue = "\(Int((config.almostMaximizeWidth * 100).rounded())) %"
        almostHeightValue.stringValue = "\(Int((config.almostMaximizeHeight * 100).rounded())) %"
        sizeStepValue.stringValue = "\(Int(config.sizeStep)) pt"
    }

    @objc private func openFile() {
        onOpenFile?()
    }

    // MARK: Showing the config

    private func refresh() {
        let layout = Shortcut.layoutMap()
        if characters.isEmpty { characters = Shortcut.characterMap() }
        for (action, field) in fields {
            let text = config.shortcuts[action.rawValue] ?? ""
            let shortcut = text.isEmpty ? nil : try? Shortcut(parsing: text, layout: layout)
            field.show(shortcut, invalidText: shortcut == nil && !text.isEmpty ? text : nil, characters: characters)
            let problem = problems[action.rawValue]
            warnings[action]?.isHidden = problem == nil
            warnings[action]?.toolTip = problem
        }
        launchAtLogin.state = config.launchAtLogin ? .on : .off
        menuBarIcon.state = config.menuBarIcon ? .on : .off
        halvesAcross.state = config.halvesAcrossDisplays ? .on : .off
        moveCursor.state = config.moveCursorAcrossDisplays ? .on : .off
        if sliderSave == nil {
            almostWidth.doubleValue = config.almostMaximizeWidth * 100
            almostHeight.doubleValue = config.almostMaximizeHeight * 100
            sizeStep.doubleValue = config.sizeStep
            showSliderValues()
        }
    }
}

/// Small pictures of where an action puts the window, like the ones in Rectangle's settings.
enum ActionIcon {
    @MainActor
    static func image(for action: Action) -> NSImage {
        if let symbol = symbols[action] {
            let image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) ?? NSImage()
            return image.withSymbolConfiguration(.init(pointSize: 13, weight: .regular)) ?? image
        }
        let unit = units[action] ?? CGRect(x: 0, y: 0, width: 1, height: 1)
        let image = NSImage(size: NSSize(width: 24, height: 16), flipped: true) { bounds in
            let screen = bounds.insetBy(dx: 0.75, dy: 0.75)
            let outline = NSBezierPath(roundedRect: screen, xRadius: 2.5, yRadius: 2.5)
            outline.lineWidth = 1.5
            NSColor.black.setStroke()
            outline.stroke()
            let inner = screen.insetBy(dx: 2.25, dy: 2.25)
            let rect = CGRect(x: inner.minX + unit.minX * inner.width, y: inner.minY + unit.minY * inner.height,
                              width: unit.width * inner.width, height: unit.height * inner.height)
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), xRadius: 1, yRadius: 1).fill()
            return true
        }
        image.isTemplate = true
        return image
    }

    private static let symbols: [Action: String] = [
        .larger: "arrow.up.left.and.arrow.down.right",
        .smaller: "arrow.down.right.and.arrow.up.left",
        .restore: "arrow.uturn.backward",
        .nextDisplay: "arrow.right.square",
        .previousDisplay: "arrow.left.square",
    ]

    /// Where the window goes, as fractions of the screen (origin top left).
    private static let units: [Action: CGRect] = [
        .leftHalf: CGRect(x: 0, y: 0, width: 0.5, height: 1),
        .rightHalf: CGRect(x: 0.5, y: 0, width: 0.5, height: 1),
        .centerHalf: CGRect(x: 0.25, y: 0, width: 0.5, height: 1),
        .topHalf: CGRect(x: 0, y: 0, width: 1, height: 0.5),
        .bottomHalf: CGRect(x: 0, y: 0.5, width: 1, height: 0.5),
        .topLeft: CGRect(x: 0, y: 0, width: 0.5, height: 0.5),
        .topRight: CGRect(x: 0.5, y: 0, width: 0.5, height: 0.5),
        .bottomLeft: CGRect(x: 0, y: 0.5, width: 0.5, height: 0.5),
        .bottomRight: CGRect(x: 0.5, y: 0.5, width: 0.5, height: 0.5),
        .firstThird: CGRect(x: 0, y: 0, width: 1.0 / 3, height: 1),
        .centerThird: CGRect(x: 1.0 / 3, y: 0, width: 1.0 / 3, height: 1),
        .lastThird: CGRect(x: 2.0 / 3, y: 0, width: 1.0 / 3, height: 1),
        .firstTwoThirds: CGRect(x: 0, y: 0, width: 2.0 / 3, height: 1),
        .lastTwoThirds: CGRect(x: 1.0 / 3, y: 0, width: 2.0 / 3, height: 1),
        .maximize: CGRect(x: 0, y: 0, width: 1, height: 1),
        .almostMaximize: CGRect(x: 0.1, y: 0.12, width: 0.8, height: 0.76),
        .maximizeHeight: CGRect(x: 0.33, y: 0, width: 0.34, height: 1),
        .center: CGRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5),
    ]
}
