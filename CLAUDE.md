# Rectmangle

Minimaler Nachbau von Rectangle (Fenster per Kürzel anordnen), Swift/AppKit per SwiftPM, ohne Netzwerk. Gebaut mit `./build.sh`, installiert mit `./build.sh --install` nach `~/Applications`.

- Kürzel: Carbon `RegisterEventHotKey` (`HotKeys.swift`), Fenster: Accessibility-API (`Window.swift`), Logik: `WindowManager.swift`. Rechnet durchgehend in AX-Koordinaten (Ursprung oben links am Hauptbildschirm).
- Konfiguration `~/.config/rectmangle/config.json`, Standard in `Config.swift`. Die Kürzel dort entsprechen den Rectangle-Einstellungen des Nutzers (aus `defaults read com.knollsoft.Rectangle`, Stand 2026-10-18).
- Signiert mit Developer ID, damit die Bedienungshilfen-Freigabe Builds überlebt.
- `Rectmangle --check` zeigt, wie die Konfiguration verstanden wird.
