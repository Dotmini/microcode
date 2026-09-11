#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_PATH="${APP_PATH:-/Volumes/MicroCodeBuild/apps/MicroCode.app}"
OUTPUT_DIR="${OUTPUT_DIR:-$ROOT_DIR/Dist/DeveloperPreview}"
RESOURCES_DIR="$ROOT_DIR/Installer/DeveloperPreview"
APP_NAME="MicroCode"
BUNDLE_ID="com.dotmini.microcode"

# Distribution must never contain a developer or service credential.  Keep the
# patterns deliberately strict so random bytes in signed Mach-O binaries do not
# create false positives.  The gate emits no matching content on failure.
assert_no_embedded_secrets() {
  local credential_file
  credential_file="$(find "$APP_PATH" -type f \( \
    -name '.env' -o -name '.env.*' -o -name '*.pem' -o -name '*.key' -o \
    -name '*.p12' -o -name '*.pfx' -o -name 'credentials.json' -o \
    -name 'service-account*.json' \
  \) -print -quit)"

  if [[ -n "$credential_file" ]]; then
    echo "Refusing to package: an environment or credential file is inside the app bundle." >&2
    exit 1
  fi

  local secret_pattern
  secret_pattern='sk-proj-[A-Za-z0-9_-]{40,}|sk-[A-Za-z0-9]{48,}|AIza[A-Za-z0-9_-]{35}|ghp_[A-Za-z0-9]{36}|github_pat_[A-Za-z0-9_]{82}|AKIA[0-9A-Z]{16}|xox[baprs]-[A-Za-z0-9-]{20,}'
  if find "$APP_PATH" -type f -print0 | xargs -0 strings 2>/dev/null | LC_ALL=C grep -Eq "$secret_pattern"; then
    echo "Refusing to package: a credential-shaped value was detected in the app bundle." >&2
    echo "Remove it and use runtime configuration or Keychain storage instead." >&2
    exit 1
  fi
}

if [[ ! -d "$APP_PATH" ]]; then
  echo "Missing app bundle: $APP_PATH" >&2
  echo "Run ./build.sh first, or set APP_PATH to a built MicroCode.app." >&2
  exit 1
fi

echo "Auditing app bundle for embedded credentials…"
assert_no_embedded_secrets

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_PATH/Contents/Info.plist")"
BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP_PATH/Contents/Info.plist")"
RELEASE_NAME="$APP_NAME-$VERSION-DeveloperPreview"
WORK_DIR="$(mktemp -d /tmp/microcode-preview.XXXXXX)"
trap 'rm -rf "$WORK_DIR"' EXIT

mkdir -p "$OUTPUT_DIR/packages" "$OUTPUT_DIR/dmg"
rm -f "$OUTPUT_DIR/$RELEASE_NAME.pkg" "$OUTPUT_DIR/$RELEASE_NAME.dmg"
COMPONENT_PKG="$OUTPUT_DIR/packages/$APP_NAME-component.pkg"
rm -f "$COMPONENT_PKG"

echo "Creating component installer…"
pkgbuild --component "$APP_PATH" --install-location /Applications --identifier "$BUNDLE_ID" --version "$VERSION" "$COMPONENT_PKG"

cat > "$WORK_DIR/distribution.xml" <<EOF
<?xml version="1.0" encoding="utf-8"?>
<installer-gui-script minSpecVersion="1">
  <title>MicroCode Developer Preview</title>
  <options customize="never" require-scripts="false" hostArchitectures="arm64"/>
  <welcome file="Welcome.html" mime-type="text/html"/>
  <readme file="ReadMe.html" mime-type="text/html"/>
  <license file="License.html" mime-type="text/html"/>
  <choices-outline><line choice="default"/></choices-outline>
  <choice id="default" title="MicroCode Developer Preview" description="Install MicroCode in Applications."><pkg-ref id="$BUNDLE_ID"/></choice>
  <pkg-ref id="$BUNDLE_ID" version="$VERSION" onConclusion="none">$APP_NAME-component.pkg</pkg-ref>
</installer-gui-script>
EOF

echo "Creating product installer…"
productbuild --distribution "$WORK_DIR/distribution.xml" --resources "$RESOURCES_DIR" --package-path "$OUTPUT_DIR/packages" "$OUTPUT_DIR/$RELEASE_NAME.pkg"

echo "Creating DMG…"
DMG_STAGE="$WORK_DIR/dmg"
mkdir -p "$DMG_STAGE"
cp -R "$APP_PATH" "$DMG_STAGE/$APP_NAME.app"
cp "$OUTPUT_DIR/$RELEASE_NAME.pkg" "$DMG_STAGE/Install $APP_NAME Developer Preview.pkg"
cp "$RESOURCES_DIR/ReadMe.html" "$DMG_STAGE/Read Me.html"
ln -s /Applications "$DMG_STAGE/Applications"
hdiutil create -volname "$APP_NAME Developer Preview" -srcfolder "$DMG_STAGE" -ov -format UDZO "$OUTPUT_DIR/$RELEASE_NAME.dmg" >/dev/null

codesign --verify --deep --strict --verbose=2 "$APP_PATH"
pkgutil --check-signature "$OUTPUT_DIR/$RELEASE_NAME.pkg" || true
echo "Developer Preview artifacts created:"
echo "  PKG: $OUTPUT_DIR/$RELEASE_NAME.pkg"
echo "  DMG: $OUTPUT_DIR/$RELEASE_NAME.dmg"
echo "  Version: $VERSION (Build $BUILD)"
echo "Note: no Developer ID Installer certificate was found; these preview artifacts are not notarized."
