import AppKit

// `Rectmangle --check` prints how the config is understood, without starting the app.
if CommandLine.arguments.contains("--check") {
    do {
        let config = try Config.load()
        let layout = Shortcut.layoutMap()
        for action in Action.allCases {
            let text = config.shortcuts[action.rawValue] ?? ""
            guard !text.isEmpty else { continue }
            do {
                let s = try Shortcut(parsing: text, layout: layout)
                print("\(action.rawValue): \(text) → key code \(s.keyCode), modifiers \(s.modifiers)")
            } catch {
                print("\(action.rawValue): ERROR \(error.localizedDescription)")
            }
        }
        for name in config.shortcuts.keys where Action(rawValue: name) == nil {
            print("\(name): ERROR unknown action")
        }
        exit(0)
    } catch {
        print("\(Config.url.path): \(error.localizedDescription)")
        exit(1)
    }
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}
