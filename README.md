# Rectmangle

Arrange windows with keyboard shortcuts, modelled on [Rectangle](https://rectangleapp.com). Small, no network access, no license check, no updater. One config file instead of a settings window.

- Halves, quarters, thirds, maximize, almost maximize, maximize height, larger, smaller, center, restore
- Next and previous display, the mouse pointer follows the window
- Pressing left or right half a second time moves the window on to the neighbouring display (like Rectangle with "Subsequent execution: across displays")
- Restore puts the window back to its size and position from before the first shortcut
- Launch at login, menu bar icon can be hidden

Not included: snap areas when dragging to the screen edge, gaps between windows, per-app exceptions.

## Download

With Homebrew (the cask removes the quarantine flag itself):

```sh
brew trust --cask wiredframe/tap/rectmangle
brew install --cask wiredframe/tap/rectmangle
```

Or by hand: the [releases](https://github.com/Wiredframe/rectmangle/releases) contain the app as a ZIP. Unpack it and move it to `~/Applications` or `/Applications`. It is signed with a Developer ID but not notarized, so macOS blocks the first launch. To allow it:

```sh
xattr -dr com.apple.quarantine /Applications/Rectmangle.app
```

## Build and install

Needs a Mac with Apple Silicon, macOS 13 or later and the Xcode Command Line Tools (Swift 5.9 or later).

```sh
./build.sh            # builds build/Rectmangle.app
./build.sh --install  # also copies it to ~/Applications and launches it
./build.sh --zip      # also packs build/Rectmangle-<version>.zip for a release
```

On first launch macOS asks for access under **System Settings › Privacy & Security › Accessibility**. Without it, other apps' windows cannot be moved.

That access is tied to the code signature. `build.sh` uses a "Developer ID Application" certificate if there is one, then access survives new builds. Without a certificate the app is signed ad hoc and access has to be granted again after every build (remove the old entry with "−" first). Pick another certificate with `SIGN_IDENTITY="…" ./build.sh`.

While Rectangle is running, it owns the shortcuts. Quit it first.

## Configuration

`~/.config/rectmangle/config.json`, created on first launch. Changes apply as soon as the file is saved. Without the menu bar icon, launching the app again (`open -a Rectmangle`) opens the file.

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

**Shortcuts** are modifiers plus one key:

- modifiers as symbols `⌃ ⌥ ⇧ ⌘` or as words `ctrl`, `opt`/`alt`, `shift`, `cmd`, joined with `+`
- keys: `← → ↑ ↓` or `left right up down`, `return`, `tab`, `space`, `delete`, `escape`, `home`, `end`, `pageup`, `pagedown`, `f1` to `f12`
- any other character is looked up in the current keyboard layout, so `+` means the key that types `+`
- `#30` for a raw key code
- empty text: no shortcut

**Actions:** `leftHalf`, `rightHalf`, `centerHalf`, `topHalf`, `bottomHalf`, `topLeft`, `topRight`, `bottomLeft`, `bottomRight`, `firstThird`, `centerThird`, `lastThird`, `firstTwoThirds`, `lastTwoThirds`, `maximize`, `almostMaximize`, `maximizeHeight`, `larger`, `smaller`, `center`, `restore`, `nextDisplay`, `previousDisplay`.

**Other keys:**

| Key | Meaning |
|---|---|
| `almostMaximize` | share of width and height for "almost maximize" |
| `sizeStep` | pixels per step for larger and smaller |
| `halvesAcrossDisplays` | pressing a half again moves to the next display |
| `moveCursorAcrossDisplays` | the mouse pointer follows the window to another display |
| `menuBarIcon` | icon in the menu bar |
| `launchAtLogin` | launch at login |

Check how the file is understood:

```sh
/Applications/Rectmangle.app/Contents/MacOS/Rectmangle --check
```

Quit without the menu bar icon: `pkill -x Rectmangle`.

## Scripting

Every action can be triggered by URL, for example from Raycast, Alfred or the Shortcuts app:

```sh
open -g rectmangle://leftHalf
```

Any app on the Mac can call the scheme, a website only after the browser asks. It can do nothing beyond moving the active app's window.

## Privacy

Rectmangle contains no networking code:

```sh
otool -L /Applications/Rectmangle.app/Contents/MacOS/Rectmangle   # no CFNetwork, no Network.framework
```

## License

MIT
