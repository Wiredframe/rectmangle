# Rectmangle

Fenster per Tastenkürzel anordnen, angelehnt an [Rectangle](https://rectangleapp.com). Klein, ohne Netzwerk, ohne Lizenzprüfung, ohne Updater. Eine Konfigurationsdatei statt Einstellungsfenster.

- Hälften, Viertel, Drittel, Maximieren, Nahezu maximieren, Höhe maximieren, Vergrößern, Verkleinern, Zentrieren, Wiederherstellen
- Nächster und vorheriger Bildschirm, der Mauszeiger wandert mit
- Linke oder rechte Hälfte ein zweites Mal gedrückt: Das Fenster rutscht auf den Bildschirm daneben (wie Rectangle mit „Subsequent execution: across displays“)
- Wiederherstellen setzt das Fenster auf die Größe vor dem ersten Kürzel zurück
- Beim Anmelden starten, Symbol in der Menüleiste ein- oder ausblendbar

Nicht dabei: Schnappbereiche beim Ziehen an den Rand, Abstände zwischen Fenstern, Ausnahmen je App.

## Herunterladen

Per Homebrew (entfernt die Quarantäne-Markierung selbst):

```sh
brew trust --cask wiredframe/tap/rectmangle
brew install --cask wiredframe/tap/rectmangle
```

Oder von Hand: unter [Releases](https://github.com/Wiredframe/rectmangle/releases) liegt die fertige App als ZIP. Auspacken, nach `~/Applications` oder `/Applications` legen. Sie ist mit Developer ID signiert, aber nicht notarisiert, deshalb blockiert macOS den ersten Start. Abhilfe:

```sh
xattr -dr com.apple.quarantine ~/Applications/Rectmangle.app
```

## Bauen und installieren

Braucht einen Mac mit Apple Silicon, macOS 13 oder neuer und die Command Line Tools von Xcode (Swift 5.9 oder neuer).

```sh
./build.sh            # baut build/Rectmangle.app
./build.sh --install  # zusätzlich nach ~/Applications und starten
./build.sh --zip      # zusätzlich build/Rectmangle-<version>.zip für ein Release
```

Beim ersten Start fragt macOS nach der Freigabe unter **Systemeinstellungen › Datenschutz & Sicherheit › Bedienungshilfen**. Ohne sie lassen sich fremde Fenster nicht bewegen.

Die Freigabe hängt an der Code-Signatur. `build.sh` nimmt ein vorhandenes „Developer ID Application“-Zertifikat, dann bleibt sie über neue Builds erhalten. Ohne Zertifikat wird ad hoc signiert, dann muss die Freigabe nach jedem Build neu erteilt werden (alten Eintrag vorher mit „−“ entfernen). Ein anderes Zertifikat lässt sich mit `SIGN_IDENTITY="…" ./build.sh` wählen.

Läuft Rectangle noch, gehören ihm die Kürzel. Vorher beenden.

## Konfiguration

`~/.config/rectmangle/config.json`, wird beim ersten Start angelegt. Änderungen gelten sofort nach dem Speichern. Ohne Menüleistensymbol öffnet ein erneuter Start der App (`open -a Rectmangle`) die Datei.

```json
{
  "shortcuts": {
    "leftHalf": "⌃⌥←",
    "larger": "⌃⌥⌘+",
    "nextDisplay": "ctrl+cmd+right",
    "centerHalf": ""
  },
  "almostMaximize": { "width": 0.9, "height": 0.9 },
  "sizeStep": 30,
  "halvesAcrossDisplays": true,
  "moveCursorAcrossDisplays": true,
  "menuBarIcon": true,
  "launchAtLogin": false
}
```

**Kürzel** bestehen aus Sondertasten und einer Taste:

- Sondertasten als Zeichen `⌃ ⌥ ⇧ ⌘` oder als Wörter `ctrl`, `opt`/`alt`, `shift`, `cmd`, verbunden mit `+`
- Tasten: `← → ↑ ↓` bzw. `left right up down`, `return`, `tab`, `space`, `delete`, `escape`, `home`, `end`, `pageup`, `pagedown`, `f1` bis `f12`
- jedes andere Zeichen wird über die aktuelle Tastaturbelegung gesucht, `+` meint also die Taste, auf der `+` steht
- `#30` für einen rohen Tastencode
- leerer Text: kein Kürzel

**Aktionen:** `leftHalf`, `rightHalf`, `centerHalf`, `topHalf`, `bottomHalf`, `topLeft`, `topRight`, `bottomLeft`, `bottomRight`, `firstThird`, `centerThird`, `lastThird`, `firstTwoThirds`, `lastTwoThirds`, `maximize`, `almostMaximize`, `maximizeHeight`, `larger`, `smaller`, `center`, `restore`, `nextDisplay`, `previousDisplay`.

**Weitere Schlüssel:**

| Schlüssel | Bedeutung |
|---|---|
| `almostMaximize` | Anteil von Breite und Höhe für „Nahezu maximieren“ |
| `sizeStep` | Pixel je Schritt bei Vergrößern und Verkleinern |
| `halvesAcrossDisplays` | Hälfte erneut drücken wechselt den Bildschirm |
| `moveCursorAcrossDisplays` | Mauszeiger folgt dem Fenster auf einen anderen Bildschirm |
| `menuBarIcon` | Symbol in der Menüleiste |
| `launchAtLogin` | beim Anmelden starten |

Prüfen, wie die Datei verstanden wird:

```sh
~/Applications/Rectmangle.app/Contents/MacOS/Rectmangle --check
```

Beenden ohne Menüleistensymbol: `pkill -x Rectmangle`.

## Aus Skripten aufrufen

Jede Aktion lässt sich per URL auslösen, etwa aus Raycast, Alfred oder der App Kurzbefehle:

```sh
open -g rectmangle://leftHalf
```

Das Schema kann jede App auf dem Mac aufrufen, eine Website nur nach Rückfrage des Browsers. Mehr als Fenster des aktiven Programms verschieben lässt sich darüber nicht.

## Privatsphäre

Rectmangle enthält keinen Netzwerkcode:

```sh
otool -L ~/Applications/Rectmangle.app/Contents/MacOS/Rectmangle   # kein CFNetwork, kein Network.framework
```

## Lizenz

MIT
