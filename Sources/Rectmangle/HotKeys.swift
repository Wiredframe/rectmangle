import Carbon
import AppKit

struct Shortcut {
    let keyCode: UInt32
    let modifiers: UInt32 // Carbon modifier mask

    struct ParseError: LocalizedError {
        let errorDescription: String?
    }

    private static let modifierSymbols: [Character: Int] = [
        "⌃": controlKey, "⌥": optionKey, "⇧": shiftKey, "⌘": cmdKey,
    ]

    private static let modifierWords: [String: Int] = [
        "ctrl": controlKey, "control": controlKey,
        "opt": optionKey, "option": optionKey, "alt": optionKey,
        "shift": shiftKey,
        "cmd": cmdKey, "command": cmdKey,
    ]

    private static let namedKeys: [String: Int] = [
        "←": kVK_LeftArrow, "left": kVK_LeftArrow,
        "→": kVK_RightArrow, "right": kVK_RightArrow,
        "↑": kVK_UpArrow, "up": kVK_UpArrow,
        "↓": kVK_DownArrow, "down": kVK_DownArrow,
        "return": kVK_Return, "enter": kVK_Return, "↩": kVK_Return,
        "tab": kVK_Tab, "space": kVK_Space,
        "delete": kVK_Delete, "backspace": kVK_Delete, "forwarddelete": kVK_ForwardDelete,
        "escape": kVK_Escape, "esc": kVK_Escape,
        "home": kVK_Home, "end": kVK_End, "pageup": kVK_PageUp, "pagedown": kVK_PageDown,
        "f1": kVK_F1, "f2": kVK_F2, "f3": kVK_F3, "f4": kVK_F4, "f5": kVK_F5, "f6": kVK_F6,
        "f7": kVK_F7, "f8": kVK_F8, "f9": kVK_F9, "f10": kVK_F10, "f11": kVK_F11, "f12": kVK_F12,
    ]

    init(keyCode: UInt32, flags: NSEvent.ModifierFlags) {
        var mods = 0
        if flags.contains(.control) { mods |= controlKey }
        if flags.contains(.option) { mods |= optionKey }
        if flags.contains(.shift) { mods |= shiftKey }
        if flags.contains(.command) { mods |= cmdKey }
        self.keyCode = keyCode
        modifiers = UInt32(mods)
    }

    /// Accepts "⌃⌥←", "ctrl+opt+left", "ctrl+opt+cmd++" or a raw key code like "⌃⌥#30".
    /// Characters are looked up in the current keyboard layout, so "+" means the key that types "+".
    init(parsing text: String, layout: [String: UInt32]) throws {
        var rest = Substring(text.trimmingCharacters(in: .whitespaces))
        var mods = 0
        while rest.count > 1 {
            if let m = Self.modifierSymbols[rest.first!] {
                mods |= m
                rest.removeFirst()
            } else if let plus = rest.firstIndex(of: "+"),
                      rest.index(after: plus) != rest.endIndex,
                      let m = Self.modifierWords[rest[..<plus].lowercased()] {
                mods |= m
                rest = rest[rest.index(after: plus)...]
            } else {
                break
            }
        }
        guard mods != 0 else { throw ParseError(errorDescription: "\"\(text)\" needs at least one modifier (⌃⌥⇧⌘)") }

        let key = rest.lowercased()
        let code: UInt32? = if let named = Self.namedKeys[key] {
            UInt32(named)
        } else if key.hasPrefix("#"), key.count > 1 { // a lone "#" is the key that types it
            UInt32(key.dropFirst())
        } else {
            // On layouts without an unshifted "+" (US), fall back to the "=" key like Rectangle does.
            layout[key] ?? (key == "+" ? layout["="] : nil)
        }
        guard let code else { throw ParseError(errorDescription: "unknown key \"\(rest)\" in \"\(text)\"") }
        keyCode = code
        modifiers = UInt32(mods)
    }

    private static let menuKeys: [Int: Int] = [
        kVK_LeftArrow: NSLeftArrowFunctionKey, kVK_RightArrow: NSRightArrowFunctionKey,
        kVK_UpArrow: NSUpArrowFunctionKey, kVK_DownArrow: NSDownArrowFunctionKey,
        kVK_Return: 0x0D, kVK_Tab: 0x09, kVK_Space: 0x20, kVK_Delete: 0x08, kVK_ForwardDelete: NSDeleteFunctionKey,
        kVK_Escape: 0x1B, kVK_Home: NSHomeFunctionKey, kVK_End: NSEndFunctionKey,
        kVK_PageUp: NSPageUpFunctionKey, kVK_PageDown: NSPageDownFunctionKey,
        kVK_F1: NSF1FunctionKey, kVK_F2: NSF2FunctionKey, kVK_F3: NSF3FunctionKey, kVK_F4: NSF4FunctionKey,
        kVK_F5: NSF5FunctionKey, kVK_F6: NSF6FunctionKey, kVK_F7: NSF7FunctionKey, kVK_F8: NSF8FunctionKey,
        kVK_F9: NSF9FunctionKey, kVK_F10: NSF10FunctionKey, kVK_F11: NSF11FunctionKey, kVK_F12: NSF12FunctionKey,
    ]

    /// The shortcut as a menu key equivalent, so the menu can show it. `characters` maps key codes back to the layout.
    func menuKey(characters: [UInt32: String]) -> (key: String, modifiers: NSEvent.ModifierFlags)? {
        let key: String
        if let special = Self.menuKeys[Int(keyCode)], let scalar = UnicodeScalar(special) {
            key = String(Character(scalar))
        } else if let character = characters[keyCode] {
            key = character
        } else {
            return nil
        }
        var flags: NSEvent.ModifierFlags = []
        if modifiers & UInt32(controlKey) != 0 { flags.insert(.control) }
        if modifiers & UInt32(optionKey) != 0 { flags.insert(.option) }
        if modifiers & UInt32(shiftKey) != 0 { flags.insert(.shift) }
        if modifiers & UInt32(cmdKey) != 0 { flags.insert(.command) }
        return (key, flags)
    }

    /// Names written to the config, the parser reads them back via `namedKeys`.
    private static let configNames: [Int: String] = [
        kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
        kVK_Return: "return", kVK_Tab: "tab", kVK_Space: "space", kVK_Delete: "delete",
        kVK_ForwardDelete: "forwarddelete", kVK_Escape: "escape", kVK_Home: "home", kVK_End: "end",
        kVK_PageUp: "pageup", kVK_PageDown: "pagedown",
        kVK_F1: "f1", kVK_F2: "f2", kVK_F3: "f3", kVK_F4: "f4", kVK_F5: "f5", kVK_F6: "f6",
        kVK_F7: "f7", kVK_F8: "f8", kVK_F9: "f9", kVK_F10: "f10", kVK_F11: "f11", kVK_F12: "f12",
    ]

    private static let displayNames: [Int: String] = [
        kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
        kVK_Return: "↩", kVK_Tab: "⇥", kVK_Space: "Space", kVK_Delete: "⌫", kVK_ForwardDelete: "⌦",
        kVK_Escape: "⎋", kVK_Home: "↖", kVK_End: "↘", kVK_PageUp: "⇞", kVK_PageDown: "⇟",
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6",
        kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
    ]

    static func modifierSymbols(_ mods: UInt32) -> String {
        var text = ""
        if mods & UInt32(controlKey) != 0 { text += "⌃" }
        if mods & UInt32(optionKey) != 0 { text += "⌥" }
        if mods & UInt32(shiftKey) != 0 { text += "⇧" }
        if mods & UInt32(cmdKey) != 0 { text += "⌘" }
        return text
    }

    /// The text for the config file, e.g. "⌃⌥←" or "⌃⌥⌘+".
    func configText(characters: [UInt32: String]) -> String {
        let key = Self.configNames[Int(keyCode)] ?? characters[keyCode] ?? "#\(keyCode)"
        return Self.modifierSymbols(modifiers) + key
    }

    /// The text for the settings window, e.g. "⌃⌥Space" or "⌃⌥⌘A".
    func displayText(characters: [UInt32: String]) -> String {
        let key = Self.displayNames[Int(keyCode)] ?? characters[keyCode]?.uppercased() ?? "#\(keyCode)"
        return Self.modifierSymbols(modifiers) + key
    }

    func conflicts(with other: Shortcut) -> Bool {
        keyCode == other.keyCode && modifiers == other.modifiers
    }

    /// Maps key codes back to the characters of the current keyboard layout.
    static func characterMap() -> [UInt32: String] {
        var characters: [UInt32: String] = [:]
        for (character, code) in layoutMap() where characters[code] == nil { characters[code] = character }
        return characters
    }

    /// Maps the characters of the current keyboard layout to key codes.
    static func layoutMap() -> [String: UInt32] {
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let pointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return [:] }
        let data = Unmanaged<CFData>.fromOpaque(pointer).takeUnretainedValue() as Data
        var map: [String: UInt32] = [:]
        data.withUnsafeBytes { raw in
            guard let layout = raw.bindMemory(to: UCKeyboardLayout.self).baseAddress else { return }
            // Ascending order, so main keys win over keypad keys that type the same character.
            for code in 0..<128 {
                var deadKeys: UInt32 = 0
                var chars = [UniChar](repeating: 0, count: 4)
                var length = 0
                let status = UCKeyTranslate(layout, UInt16(code), UInt16(kUCKeyActionDisplay), 0, UInt32(LMGetKbdType()),
                                            OptionBits(1 << kUCKeyTranslateNoDeadKeysBit), &deadKeys, 4, &length, &chars)
                guard status == noErr, length > 0 else { continue }
                let string = String(utf16CodeUnits: chars, count: length).lowercased()
                guard string.unicodeScalars.allSatisfy({ $0.value > 0x20 && $0.value != 0x7F }) else { continue }
                if map[string] == nil { map[string] = UInt32(code) }
            }
        }
        return map
    }
}

@MainActor
final class HotKeyCenter {
    private var refs: [EventHotKeyRef] = []
    private var handlers: [UInt32: () -> Void] = [:]
    private var nextID: UInt32 = 1

    init() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, userData in
            guard let event, let userData else { return OSStatus(eventNotHandledErr) }
            var hotKey = EventHotKeyID()
            let status = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                           nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKey)
            guard status == noErr else { return status }
            let center = Unmanaged<HotKeyCenter>.fromOpaque(userData).takeUnretainedValue()
            MainActor.assumeIsolated { center.handlers[hotKey.id]?() }
            return noErr
        }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), nil)
    }

    func register(_ shortcut: Shortcut, handler: @escaping () -> Void) -> Bool {
        var ref: EventHotKeyRef?
        let id = EventHotKeyID(signature: OSType(0x524D_474C), id: nextID) // "RMGL"
        let status = RegisterEventHotKey(shortcut.keyCode, shortcut.modifiers, id, GetApplicationEventTarget(), 0, &ref)
        guard status == noErr, let ref else { return false }
        refs.append(ref)
        handlers[nextID] = handler
        nextID += 1
        return true
    }

    func unregisterAll() {
        refs.forEach { UnregisterEventHotKey($0) }
        refs = []
        handlers = [:]
    }
}
