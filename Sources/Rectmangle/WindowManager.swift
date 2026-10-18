import AppKit

enum Action: String, CaseIterable {
    case leftHalf, rightHalf, centerHalf, topHalf, bottomHalf
    case topLeft, topRight, bottomLeft, bottomRight
    case firstThird, centerThird, lastThird, firstTwoThirds, lastTwoThirds
    case maximize, almostMaximize, maximizeHeight, larger, smaller, center, restore
    case nextDisplay, previousDisplay

    /// Actions that describe a place on the screen and can be repeated on another display.
    var isPlacement: Bool {
        switch self {
        case .larger, .smaller, .restore, .nextDisplay, .previousDisplay: false
        default: true
        }
    }
}

/// A display in Accessibility coordinates (origin top left of the main display, y grows downwards).
struct Screen: Equatable {
    let frame: CGRect
    let visible: CGRect

    static func all() -> [Screen] {
        guard let mainHeight = NSScreen.screens.first?.frame.maxY else { return [] }
        func flip(_ r: CGRect) -> CGRect {
            CGRect(x: r.minX, y: mainHeight - r.maxY, width: r.width, height: r.height)
        }
        return NSScreen.screens
            .map { Screen(frame: flip($0.frame), visible: flip($0.visibleFrame)) }
            .sorted { ($0.frame.minX, $0.frame.minY) < ($1.frame.minX, $1.frame.minY) }
    }
}

@MainActor
final class WindowManager {
    var config = Config()

    /// What Rectmangle last did with a window, to detect repeated shortcuts and manual moves.
    private struct Record {
        var action: Action?
        var frame: CGRect
    }

    private var records: [CGWindowID: Record] = [:]
    private var restoreFrames: [CGWindowID: CGRect] = [:]

    func perform(_ action: Action) {
        guard AXIsProcessTrusted() else {
            AXPermission.ensureTrusted(prompt: true)
            return
        }
        guard let window = Window.focused(), let frame = window.frame else {
            NSSound.beep()
            return
        }
        let screens = Screen.all()
        guard let screen = screens.max(by: { overlap($0.frame, frame) < overlap($1.frame, frame) }),
              let index = screens.firstIndex(of: screen) else { return }
        // Window ids of closed windows are never reused soon, but the lists should not grow forever.
        if records.count > 500 { records.removeAll() }
        if restoreFrames.count > 500 { restoreFrames.removeAll() }

        let id = window.id
        let record = id.flatMap { records[$0] }
        let untouched = record.map { $0.frame.isClose(to: frame) } ?? false

        if action == .restore {
            guard let id, let saved = restoreFrames.removeValue(forKey: id) else {
                NSSound.beep()
                return
            }
            records[id] = nil
            window.setFrame(saved)
            return
        }
        // Remember the frame from before Rectmangle touched the window, or after the user moved it.
        if let id, !untouched {
            restoreFrames[id] = frame
        }

        var target = screen
        var placed = action
        var rect: CGRect?

        switch action {
        case .nextDisplay, .previousDisplay:
            guard screens.count > 1 else { return }
            let step = action == .nextDisplay ? 1 : -1
            target = screens[(index + step + screens.count) % screens.count]
            let carried = carry(frame, from: screen.visible, to: target.visible)
            if untouched, let previous = record?.action {
                placed = previous
                rect = self.rect(for: previous, frame: carried, in: target.visible)
            } else {
                placed = action
                rect = carried
            }

        case .leftHalf, .rightHalf:
            // Like Rectangle: pressing a half again moves the window on to the neighbouring display.
            if config.halvesAcrossDisplays, untouched, record?.action == action,
               let neighbour = neighbour(of: screen, in: screens, toTheLeft: action == .leftHalf) {
                target = neighbour
                placed = action == .leftHalf ? .rightHalf : .leftHalf
            }
            rect = self.rect(for: placed, frame: frame, in: target.visible)

        default:
            rect = self.rect(for: action, frame: frame, in: screen.visible)
        }

        guard let rect else { return }
        window.setFrame(rect)
        var actual = window.frame ?? rect
        // Windows with a minimum size can end up wider than asked and stick out of the screen.
        let fitted = fit(actual, into: target.visible)
        if fitted != actual {
            window.setFrame(fitted)
            actual = window.frame ?? fitted
        }
        if let id {
            records[id] = Record(action: placed.isPlacement ? placed : nil, frame: actual)
        }
        if target != screen, config.moveCursorAcrossDisplays {
            CGWarpMouseCursorPosition(CGPoint(x: actual.midX, y: actual.midY))
        }
    }

    private func rect(for action: Action, frame: CGRect, in v: CGRect) -> CGRect? {
        let halfW = (v.width / 2).rounded(.down), halfH = (v.height / 2).rounded(.down)
        let thirdW = (v.width / 3).rounded(.down)

        switch action {
        case .leftHalf: return CGRect(x: v.minX, y: v.minY, width: halfW, height: v.height)
        case .rightHalf: return CGRect(x: v.minX + halfW, y: v.minY, width: v.width - halfW, height: v.height)
        case .centerHalf: return CGRect(x: v.minX + (v.width / 4).rounded(.down), y: v.minY, width: halfW, height: v.height)
        case .topHalf: return CGRect(x: v.minX, y: v.minY, width: v.width, height: halfH)
        case .bottomHalf: return CGRect(x: v.minX, y: v.minY + halfH, width: v.width, height: v.height - halfH)

        case .topLeft: return CGRect(x: v.minX, y: v.minY, width: halfW, height: halfH)
        case .topRight: return CGRect(x: v.minX + halfW, y: v.minY, width: v.width - halfW, height: halfH)
        case .bottomLeft: return CGRect(x: v.minX, y: v.minY + halfH, width: halfW, height: v.height - halfH)
        case .bottomRight: return CGRect(x: v.minX + halfW, y: v.minY + halfH, width: v.width - halfW, height: v.height - halfH)

        case .firstThird: return CGRect(x: v.minX, y: v.minY, width: thirdW, height: v.height)
        case .centerThird: return CGRect(x: v.minX + thirdW, y: v.minY, width: thirdW, height: v.height)
        case .lastThird: return CGRect(x: v.minX + 2 * thirdW, y: v.minY, width: v.width - 2 * thirdW, height: v.height)
        case .firstTwoThirds: return CGRect(x: v.minX, y: v.minY, width: 2 * thirdW, height: v.height)
        case .lastTwoThirds: return CGRect(x: v.minX + thirdW, y: v.minY, width: v.width - thirdW, height: v.height)

        case .maximize: return v
        case .almostMaximize:
            let w = (v.width * config.almostMaximizeWidth).rounded(), h = (v.height * config.almostMaximizeHeight).rounded()
            return CGRect(x: v.midX - w / 2, y: v.midY - h / 2, width: w, height: h).integral
        case .maximizeHeight: return CGRect(x: frame.minX, y: v.minY, width: frame.width, height: v.height)
        case .center:
            let w = min(frame.width, v.width), h = min(frame.height, v.height)
            return CGRect(x: v.midX - w / 2, y: v.midY - h / 2, width: w, height: h).integral

        case .larger, .smaller:
            let d = action == .larger ? config.sizeStep : -config.sizeStep
            guard let x = resize(frame.minX, frame.maxX, within: v.minX, v.maxX, by: d, minimum: 200),
                  let y = resize(frame.minY, frame.maxY, within: v.minY, v.maxY, by: d, minimum: 150) else { return nil }
            return CGRect(x: x.lo, y: y.lo, width: x.hi - x.lo, height: y.hi - y.lo).integral

        case .restore, .nextDisplay, .previousDisplay: return nil
        }
    }

    /// Grows or shrinks one axis. Edges touching the screen stay there, otherwise the change is split.
    private func resize(_ lo: CGFloat, _ hi: CGFloat, within vlo: CGFloat, _ vhi: CGFloat,
                        by d: CGFloat, minimum: CGFloat) -> (lo: CGFloat, hi: CGFloat)? {
        let atLo = abs(lo - vlo) < 2, atHi = abs(hi - vhi) < 2
        var lo = lo, hi = hi
        switch (atLo, atHi) {
        case (true, false): hi += d
        case (false, true): lo -= d
        default: lo -= d / 2; hi += d / 2
        }
        lo = max(lo, vlo)
        hi = min(hi, vhi)
        return hi - lo >= minimum ? (lo, hi) : nil
    }

    /// Moves a frame to another display, keeping its relative position and shrinking it if needed.
    private func carry(_ frame: CGRect, from s: CGRect, to t: CGRect) -> CGRect {
        let w = min(frame.width, t.width), h = min(frame.height, t.height)
        func relative(_ pos: CGFloat, _ start: CGFloat, _ free: CGFloat) -> CGFloat {
            free > 0 ? min(max((pos - start) / free, 0), 1) : 0.5
        }
        let rx = relative(frame.minX, s.minX, s.width - frame.width)
        let ry = relative(frame.minY, s.minY, s.height - frame.height)
        return CGRect(x: t.minX + rx * (t.width - w), y: t.minY + ry * (t.height - h), width: w, height: h).integral
    }

    /// The closest display beside this one that shares part of its height, so stacked displays don't count.
    private func neighbour(of screen: Screen, in screens: [Screen], toTheLeft: Bool) -> Screen? {
        let f = screen.frame
        return screens
            .filter { $0 != screen && $0.frame.maxY > f.minY && $0.frame.minY < f.maxY }
            .filter { toTheLeft ? $0.frame.maxX <= f.minX + 2 : $0.frame.minX >= f.maxX - 2 }
            .min { gap($0.frame, f) < gap($1.frame, f) }
    }

    private func gap(_ a: CGRect, _ b: CGRect) -> CGFloat {
        max(a.minX - b.maxX, b.minX - a.maxX)
    }

    private func fit(_ frame: CGRect, into v: CGRect) -> CGRect {
        var r = frame
        if r.maxX > v.maxX { r.origin.x = max(v.minX, v.maxX - r.width) }
        if r.maxY > v.maxY { r.origin.y = max(v.minY, v.maxY - r.height) }
        if r.minX < v.minX { r.origin.x = v.minX }
        if r.minY < v.minY { r.origin.y = v.minY }
        return r
    }

    private func overlap(_ a: CGRect, _ b: CGRect) -> CGFloat {
        let i = a.intersection(b)
        return i.isNull ? 0 : i.width * i.height
    }
}

private extension CGRect {
    func isClose(to other: CGRect) -> Bool {
        abs(minX - other.minX) < 2 && abs(minY - other.minY) < 2
            && abs(width - other.width) < 2 && abs(height - other.height) < 2
    }
}
