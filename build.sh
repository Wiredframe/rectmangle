#!/bin/zsh
# Baut Rectmangle.app nach build/, mit --install zusätzlich nach ~/Applications und startet es, mit --zip als Release-ZIP.
set -euo pipefail
cd "${0:A:h}"

# Universal: Apple Silicon und Intel.
ARCHS=(--arch arm64 --arch x86_64)
swift build -c release --disable-sandbox $ARCHS
BIN="$(swift build -c release --disable-sandbox $ARCHS --show-bin-path)/Rectmangle"

APP=build/Rectmangle.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN" "$APP/Contents/MacOS/"
cp Resources/Info.plist "$APP/Contents/"

# Die Bedienungshilfen-Freigabe hängt an der Signatur. Ad hoc signiert verfällt sie bei jedem Build,
# mit einem festen Zertifikat bleibt sie erhalten. SIGN_IDENTITY setzt eins explizit.
IDENTITY="${SIGN_IDENTITY:-$(security find-identity -v -p codesigning 2>/dev/null \
    | sed -n 's/.*"\(Developer ID Application[^"]*\)".*/\1/p' | head -1)}"
codesign --force --sign "${IDENTITY:--}" --options runtime "$APP"
echo "Gebaut: $APP (signiert: ${IDENTITY:-ad hoc})"

if [[ "${1:-}" == "--install" ]]; then
    pkill -x Rectmangle || true
    mkdir -p ~/Applications
    rm -rf ~/Applications/Rectmangle.app
    ditto "$APP" ~/Applications/Rectmangle.app
    open ~/Applications/Rectmangle.app
    echo "Installiert: ~/Applications/Rectmangle.app"
fi

if [[ "${1:-}" == "--zip" ]]; then
    VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Resources/Info.plist)
    ZIP="build/Rectmangle-$VERSION.zip"
    # Ohne Extended Attributes, sonst zerstören AppleDouble-Reste im ZIP die Signatur.
    ditto -c -k --keepParent --noextattr --norsrc "$APP" "$ZIP"
    CHECK=$(mktemp -d)
    unzip -q "$ZIP" -d "$CHECK"
    codesign --verify --strict --deep "$CHECK/Rectmangle.app"
    rm -rf "$CHECK"
    echo "ZIP: $ZIP (Signatur nach dem Auspacken geprüft)"
    shasum -a 256 "$ZIP"
fi
