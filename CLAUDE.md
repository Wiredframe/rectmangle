# Rectmangle

Minimal Rectangle clone (arrange windows with shortcuts), Swift/AppKit via SwiftPM, no network access, Apple Silicon only. Build with `./build.sh`, install a test copy with `./build.sh --install` (to `~/Applications`).

- Shortcuts: Carbon `RegisterEventHotKey` (`HotKeys.swift`), windows: Accessibility API (`Window.swift`), logic: `WindowManager.swift`. Everything is computed in AX coordinates (origin top left of the main display).
- Config `~/.config/rectmangle/config.json`, defaults in `Config.swift`. The default shortcuts match the user's former Rectangle settings (from `defaults read com.knollsoft.Rectangle`, 2026-10-18).
- Signed with a Developer ID so Accessibility access survives builds. Not notarized.
- `Rectmangle --check` shows how the config is understood.
- Testing without key presses: `open -g rectmangle://<action>` against the running instance, read the window bounds of a Finder window via AppleScript (Claude may not drive System Events).
- Release: version in `Resources/Info.plist`, `./build.sh --zip` (verifies the signature after unzipping), commit, tag `vX.Y.Z`, `gh release create vX.Y.Z build/Rectmangle-X.Y.Z.zip`, then in the tap `~/Projekte/Claude Code/homebrew-tap` update version and sha256 in `Casks/rectmangle.rb`, commit `rectmangle X.Y.Z`, `brew upgrade --cask rectmangle`.
- The user runs the Homebrew cask from `/Applications` (since 2026-10-18). `./build.sh --install` puts a second copy in `~/Applications`: for testing only, remove it afterwards and relaunch `/Applications/Rectmangle.app`, otherwise the login item points to the test copy.
- Docs, UI, release notes and comments are in English.
