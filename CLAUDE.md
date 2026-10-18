# Rectmangle

Minimaler Nachbau von Rectangle (Fenster per Kürzel anordnen), Swift/AppKit per SwiftPM, ohne Netzwerk. Gebaut mit `./build.sh`, installiert mit `./build.sh --install` nach `~/Applications`.

- Kürzel: Carbon `RegisterEventHotKey` (`HotKeys.swift`), Fenster: Accessibility-API (`Window.swift`), Logik: `WindowManager.swift`. Rechnet durchgehend in AX-Koordinaten (Ursprung oben links am Hauptbildschirm).
- Konfiguration `~/.config/rectmangle/config.json`, Standard in `Config.swift`. Die Kürzel dort entsprechen den Rectangle-Einstellungen des Nutzers (aus `defaults read com.knollsoft.Rectangle`, Stand 2026-10-18).
- Signiert mit Developer ID, damit die Bedienungshilfen-Freigabe Builds überlebt.
- `Rectmangle --check` zeigt, wie die Konfiguration verstanden wird.
- Testen ohne Tastendruck: `open -g rectmangle://<aktion>` an der laufenden Instanz, Fenstergröße per AppleScript an Finder prüfen (System Events darf Claude nicht steuern).
- Release: Version in `Resources/Info.plist`, `./build.sh --zip` (prüft die Signatur nach dem Auspacken), Commit, Tag `vX.Y.Z`, `gh release create vX.Y.Z build/Rectmangle-X.Y.Z.zip`, danach im Tap `~/Projekte/Claude Code/homebrew-tap` in `Casks/rectmangle.rb` version und sha256 anpassen, Commit `rectmangle X.Y.Z`. Nicht notarisiert, die Issuer-ID zum ASC-Schlüssel `ZT3NP2DJ5P` fehlt.
