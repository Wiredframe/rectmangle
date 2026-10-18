#!/bin/zsh
# Builds Rectmangle.app into build/; --install also copies it to ~/Applications and launches it, --zip packs a release ZIP.
set -euo pipefail
cd "${0:A:h}"

# Apple Silicon only.
ARCHS=(--arch arm64)
swift build -c release --disable-sandbox $ARCHS
BIN="$(swift build -c release --disable-sandbox $ARCHS --show-bin-path)/Rectmangle"

APP=build/Rectmangle.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/"
cp Resources/Info.plist "$APP/Contents/"
cp Resources/AppIcon.icns "$APP/Contents/Resources/"
cp -R Resources/*.lproj "$APP/Contents/Resources/"

# Accessibility access is tied to the code signature. An ad hoc signature changes with every build and
# loses it, a stable certificate keeps it. SIGN_IDENTITY picks one explicitly.
IDENTITY="${SIGN_IDENTITY:-$(security find-identity -v -p codesigning 2>/dev/null \
    | sed -n 's/.*"\(Developer ID Application[^"]*\)".*/\1/p' | head -1)}"
codesign --force --sign "${IDENTITY:--}" --options runtime "$APP"
echo "Built: $APP (signed: ${IDENTITY:-ad hoc})"

if [[ "${1:-}" == "--install" ]]; then
    pkill -x Rectmangle || true
    mkdir -p ~/Applications
    rm -rf ~/Applications/Rectmangle.app
    ditto "$APP" ~/Applications/Rectmangle.app
    open ~/Applications/Rectmangle.app
    echo "Installed: ~/Applications/Rectmangle.app"
fi

if [[ "${1:-}" == "--zip" ]]; then
    VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Resources/Info.plist)
    ZIP="build/Rectmangle-$VERSION.zip"
    # No extended attributes: AppleDouble files in the ZIP would break the signature.
    ditto -c -k --keepParent --noextattr --norsrc "$APP" "$ZIP"
    CHECK=$(mktemp -d)
    unzip -q "$ZIP" -d "$CHECK"
    codesign --verify --strict --deep "$CHECK/Rectmangle.app"
    rm -rf "$CHECK"
    echo "ZIP: $ZIP (signature verified after unzipping)"
    shasum -a 256 "$ZIP"
fi
