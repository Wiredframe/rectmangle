import Foundation

struct Config: Decodable, Equatable {
    /// `RECTMANGLE_CONFIG` points to another file, for trying things out without touching the real one.
    static let url = ProcessInfo.processInfo.environment["RECTMANGLE_CONFIG"].map { URL(fileURLWithPath: $0) }
        ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config/rectmangle/config.json")

    var shortcuts: [String: String] = [:]
    var almostMaximizeWidth: Double = 0.9
    var almostMaximizeHeight: Double = 0.9
    var sizeStep: Double = 30
    var halvesAcrossDisplays = true
    var moveCursorAcrossDisplays = true
    var menuBarIcon = true
    var launchAtLogin = false

    private enum Keys: String, CodingKey {
        case shortcuts, almostMaximize, sizeStep, halvesAcrossDisplays, moveCursorAcrossDisplays, menuBarIcon, launchAtLogin
    }

    private struct Fraction: Decodable {
        var width: Double?
        var height: Double?
    }

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        shortcuts = try c.decodeIfPresent([String: String].self, forKey: .shortcuts) ?? shortcuts
        if let almost = try c.decodeIfPresent(Fraction.self, forKey: .almostMaximize) {
            almostMaximizeWidth = almost.width ?? almostMaximizeWidth
            almostMaximizeHeight = almost.height ?? almostMaximizeHeight
        }
        sizeStep = try c.decodeIfPresent(Double.self, forKey: .sizeStep) ?? sizeStep
        halvesAcrossDisplays = try c.decodeIfPresent(Bool.self, forKey: .halvesAcrossDisplays) ?? halvesAcrossDisplays
        moveCursorAcrossDisplays = try c.decodeIfPresent(Bool.self, forKey: .moveCursorAcrossDisplays) ?? moveCursorAcrossDisplays
        menuBarIcon = try c.decodeIfPresent(Bool.self, forKey: .menuBarIcon) ?? menuBarIcon
        launchAtLogin = try c.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? launchAtLogin

        // Out of range values would produce windows that are invisible or larger than any screen.
        almostMaximizeWidth = min(max(almostMaximizeWidth, 0.2), 1)
        almostMaximizeHeight = min(max(almostMaximizeHeight, 0.2), 1)
        sizeStep = min(max(sizeStep, 1), 500)
    }

    /// Reads the config, writing the default one first if there is none yet.
    static func load() throws -> Config {
        let fm = FileManager.default
        if !fm.fileExists(atPath: url.path) {
            try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try defaultText.write(to: url, atomically: true, encoding: .utf8)
        }
        do {
            return try JSONDecoder().decode(Config.self, from: Data(contentsOf: url))
        } catch let error as DecodingError {
            throw LoadError(errorDescription: describe(error))
        }
    }

    /// Writes the whole config in a fixed layout. The file watcher picks up the change as well.
    static func save(_ config: Config) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try config.text.write(to: url, atomically: true, encoding: .utf8)
    }

    struct LoadError: LocalizedError {
        let errorDescription: String?
    }

    /// JSONDecoder's own messages hide the line number and the offending key.
    private static func describe(_ error: DecodingError) -> String {
        switch error {
        case .dataCorrupted(let context):
            let underlying = context.underlyingError as NSError?
            return underlying?.userInfo[NSDebugDescriptionErrorKey] as? String ?? context.debugDescription
        case .typeMismatch(_, let context), .valueNotFound(_, let context), .keyNotFound(_, let context):
            let path = context.codingPath.map(\.stringValue).joined(separator: ".")
            return path.isEmpty ? context.debugDescription : "\(path): \(context.debugDescription)"
        @unknown default:
            return error.localizedDescription
        }
    }

    static let defaultShortcuts: [String: String] = [
        "leftHalf": "⌃⌥←", "rightHalf": "⌃⌥→", "topHalf": "⌃⌥⇧⌘↑", "bottomHalf": "⌃⌥⇧⌘↓",
        "lastThird": "⌃⌥⌘→", "firstTwoThirds": "⌃⌥⌘←",
        "maximize": "⌃⌥↑", "almostMaximize": "⌃⌥⌘↑", "larger": "⌃⌥⌘+", "smaller": "⌃⌥⌘-",
        "center": "⌃⌥⌘↓", "restore": "⌃⌥↓",
        "nextDisplay": "⌃⌘→", "previousDisplay": "⌃⌘←",
    ]

    static var defaults: Config {
        var config = Config()
        config.shortcuts = defaultShortcuts
        return config
    }

    static var defaultText: String { defaults.text }

    /// The file contents: every action in menu order, so the file doubles as a list of what exists.
    var text: String {
        func string(_ value: String) -> String {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .withoutEscapingSlashes
            return (try? encoder.encode(value)).flatMap { String(data: $0, encoding: .utf8) } ?? "\"\""
        }
        func number(_ value: Double) -> String {
            value == value.rounded() ? String(Int(value)) : String(format: "%g", value)
        }
        let groups = Action.menuGroups.map { group in
            group.map { "    \(string($0.rawValue)): \(string(shortcuts[$0.rawValue] ?? ""))" }.joined(separator: ",\n")
        }
        return """
        {
          "shortcuts": {
        \(groups.joined(separator: ",\n\n"))
          },
          "almostMaximize": { "width": \(number(almostMaximizeWidth)), "height": \(number(almostMaximizeHeight)) },
          "sizeStep": \(number(sizeStep)),
          "halvesAcrossDisplays": \(halvesAcrossDisplays),
          "moveCursorAcrossDisplays": \(moveCursorAcrossDisplays),
          "menuBarIcon": \(menuBarIcon),
          "launchAtLogin": \(launchAtLogin)
        }

        """
    }
}
