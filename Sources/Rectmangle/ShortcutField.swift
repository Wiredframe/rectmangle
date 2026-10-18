import AppKit
import Carbon

/// A field that records a shortcut, like Rectangle's: click it, press the keys.
/// Esc cancels, ⌫ without modifiers clears, the x button clears as well.
@MainActor
final class ShortcutField: NSView {
    /// Called with the new shortcut (nil: cleared). Returning false rejects it.
    var onChange: ((Shortcut?) -> Bool)?
    /// Called when recording starts and stops, so the global hotkeys can step aside meanwhile.
    var onRecording: ((Bool) -> Void)?

    private(set) var shortcut: Shortcut?
    private var invalidText: String?
    private var characters: [UInt32: String] = [:]
    private var recording = false
    private var armed = false
    private var liveModifiers: NSEvent.ModifierFlags = []

    private let label = NSTextField(labelWithString: "")
    private let clearButton = NSButton()

    override init(frame: NSRect) {
        super.init(frame: frame)
        label.alignment = .center
        label.font = .systemFont(ofSize: NSFont.systemFontSize)
        label.lineBreakMode = .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)

        clearButton.image = NSImage(systemSymbolName: "xmark.circle.fill",
                                    accessibilityDescription: String(localized: "Clear Shortcut"))
        clearButton.isBordered = false
        clearButton.imagePosition = .imageOnly
        clearButton.contentTintColor = .tertiaryLabelColor
        clearButton.target = self
        clearButton.action = #selector(clear)
        clearButton.toolTip = String(localized: "Clear Shortcut")
        clearButton.refusesFirstResponder = true
        clearButton.translatesAutoresizingMaskIntoConstraints = false
        addSubview(clearButton)

        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 150),
            heightAnchor.constraint(equalToConstant: 22),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 18),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -18),
            clearButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            clearButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            clearButton.widthAnchor.constraint(equalToConstant: 14),
            clearButton.heightAnchor.constraint(equalToConstant: 14),
        ])
        setAccessibilityRole(.button)
        refresh()
    }

    required init?(coder: NSCoder) { fatalError() }

    func show(_ shortcut: Shortcut?, invalidText: String?, characters: [UInt32: String]) {
        self.shortcut = shortcut
        self.invalidText = invalidText
        self.characters = characters
        refresh()
    }

    private func refresh() {
        let text: String
        if recording {
            let symbols = Shortcut.modifierSymbols(Shortcut(keyCode: 0, flags: liveModifiers).modifiers)
            text = symbols.isEmpty ? String(localized: "Type Shortcut") : symbols
            label.textColor = symbols.isEmpty ? .placeholderTextColor : .labelColor
        } else if let shortcut {
            text = shortcut.displayText(characters: characters)
            label.textColor = .labelColor
        } else if let invalidText {
            text = invalidText
            label.textColor = .systemRed
        } else {
            text = String(localized: "Record Shortcut")
            label.textColor = .placeholderTextColor
        }
        label.stringValue = text
        clearButton.isHidden = recording || (shortcut == nil && invalidText == nil)
        setAccessibilityLabel(text)
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 5, yRadius: 5)
        (recording ? NSColor.controlAccentColor.withAlphaComponent(0.12) : NSColor.controlBackgroundColor).setFill()
        path.fill()
        (recording ? NSColor.controlAccentColor : NSColor.separatorColor).setStroke()
        path.lineWidth = recording ? 1.5 : 1
        path.stroke()
    }

    // MARK: Recording

    override var acceptsFirstResponder: Bool { armed || recording }
    override var canBecomeKeyView: Bool { false }

    override func mouseDown(with event: NSEvent) {
        if recording {
            stop()
        } else {
            armed = true
            if window?.makeFirstResponder(self) == true { start() }
            armed = false
        }
    }

    /// Switching tabs takes the field out of the window, a hidden recording must not go on.
    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil { stop(resign: false) }
    }

    override func resignFirstResponder() -> Bool {
        if recording { stop(resign: false) }
        return true
    }

    private func start() {
        recording = true
        liveModifiers = []
        onRecording?(true)
        refresh()
    }

    private func stop(resign: Bool = true) {
        guard recording else { return }
        recording = false
        liveModifiers = []
        onRecording?(false)
        refresh()
        if resign, window?.firstResponder === self { window?.makeFirstResponder(nil) }
    }

    override func flagsChanged(with event: NSEvent) {
        guard recording else { return super.flagsChanged(with: event) }
        liveModifiers = event.modifierFlags.intersection([.control, .option, .shift, .command])
        refresh()
    }

    /// ⌘ combinations arrive here first, the window would otherwise treat them as menu keys.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard recording, event.type == .keyDown else { return super.performKeyEquivalent(with: event) }
        keyDown(with: event)
        return true
    }

    override func keyDown(with event: NSEvent) {
        guard recording else { return super.keyDown(with: event) }
        let mods = event.modifierFlags.intersection([.control, .option, .shift, .command])
        let code = Int(event.keyCode)
        if mods.isEmpty, code == kVK_Escape {
            stop()
        } else if mods.isEmpty, code == kVK_Delete || code == kVK_ForwardDelete {
            stop()
            clear()
        } else if mods.intersection([.control, .option, .command]).isEmpty || mods == .command || mods == .option {
            // A global shortcut without ⌃, ⌥ or ⌘ would swallow normal typing, ⌘ or ⌥ alone copy, quit or "€".
            NSSound.beep()
        } else {
            let shortcut = Shortcut(keyCode: UInt32(event.keyCode), flags: mods)
            stop()
            if onChange?(shortcut) != false {
                self.shortcut = shortcut
                invalidText = nil
                refresh()
            }
        }
    }

    @objc private func clear() {
        if onChange?(nil) != false {
            shortcut = nil
            invalidText = nil
            refresh()
        }
    }
}
