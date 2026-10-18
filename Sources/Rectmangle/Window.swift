import AppKit

/// Private but long-standing API, also used by Rectangle, to get a stable id for a window.
@_silgen_name("_AXUIElementGetWindow")
private func _AXUIElementGetWindow(_ element: AXUIElement, _ id: UnsafeMutablePointer<CGWindowID>) -> AXError

struct Window {
    let element: AXUIElement
    let app: AXUIElement

    static func focused() -> Window? {
        guard let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier else { return nil }
        let app = AXUIElementCreateApplication(pid)
        // An app that hangs must not block the hotkeys for long. The timeout is per element.
        AXUIElementSetMessagingTimeout(app, 1)
        for attribute in [kAXFocusedWindowAttribute, kAXMainWindowAttribute] {
            var value: CFTypeRef?
            if AXUIElementCopyAttributeValue(app, attribute as CFString, &value) == .success,
               let value, CFGetTypeID(value) == AXUIElementGetTypeID() {
                let element = value as! AXUIElement
                AXUIElementSetMessagingTimeout(element, 1)
                return Window(element: element, app: app)
            }
        }
        return nil
    }

    var id: CGWindowID? {
        var id: CGWindowID = 0
        return _AXUIElementGetWindow(element, &id) == .success ? id : nil
    }

    var frame: CGRect? {
        guard let position: CGPoint = value(kAXPositionAttribute, .cgPoint),
              let size: CGSize = value(kAXSizeAttribute, .cgSize) else { return nil }
        return CGRect(origin: position, size: size)
    }

    func setFrame(_ rect: CGRect) {
        // Apps with "enhanced user interface" (set by VoiceOver-like tools) animate and ignore parts of a resize.
        let enhanced = "AXEnhancedUserInterface" as CFString
        var flag: CFTypeRef?
        let wasEnhanced = AXUIElementCopyAttributeValue(app, enhanced, &flag) == .success && (flag as? Bool) == true
        if wasEnhanced { AXUIElementSetAttributeValue(app, enhanced, kCFBooleanFalse) }

        // Size, position, size again: the first resize may be clamped by the old display.
        set(kAXSizeAttribute, rect.size, .cgSize)
        set(kAXPositionAttribute, rect.origin, .cgPoint)
        set(kAXSizeAttribute, rect.size, .cgSize)

        if wasEnhanced { AXUIElementSetAttributeValue(app, enhanced, kCFBooleanTrue) }
    }

    private func value<T: BitwiseCopyable>(_ attribute: String, _ type: AXValueType) -> T? {
        var raw: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &raw) == .success,
              let raw, CFGetTypeID(raw) == AXValueGetTypeID() else { return nil }
        let pointer = UnsafeMutablePointer<T>.allocate(capacity: 1)
        defer { pointer.deallocate() }
        return AXValueGetValue(raw as! AXValue, type, pointer) ? pointer.pointee : nil
    }

    private func set<T: BitwiseCopyable>(_ attribute: String, _ value: T, _ type: AXValueType) {
        var value = value
        guard let axValue = AXValueCreate(type, &value) else { return }
        AXUIElementSetAttributeValue(element, attribute as CFString, axValue)
    }
}
