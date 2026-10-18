import Foundation

struct Config: Decodable {
    static let url = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".config/rectmangle/config.json")

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

    static let defaultText = """
    {
      "shortcuts": {
        "leftHalf": "⌃⌥←",
        "rightHalf": "⌃⌥→",
        "centerHalf": "",
        "topHalf": "⌃⌥⇧⌘↑",
        "bottomHalf": "⌃⌥⇧⌘↓",

        "topLeft": "",
        "topRight": "",
        "bottomLeft": "",
        "bottomRight": "",

        "firstThird": "",
        "centerThird": "",
        "lastThird": "⌃⌥⌘→",
        "firstTwoThirds": "⌃⌥⌘←",
        "lastTwoThirds": "",

        "maximize": "⌃⌥↑",
        "almostMaximize": "⌃⌥⌘↑",
        "maximizeHeight": "",
        "larger": "⌃⌥⌘+",
        "smaller": "⌃⌥⌘-",
        "center": "⌃⌥⌘↓",
        "restore": "⌃⌥↓",

        "nextDisplay": "⌃⌘→",
        "previousDisplay": "⌃⌘←"
      },
      "almostMaximize": { "width": 0.9, "height": 0.9 },
      "sizeStep": 30,
      "halvesAcrossDisplays": true,
      "moveCursorAcrossDisplays": true,
      "menuBarIcon": true,
      "launchAtLogin": false
    }

    """
}
