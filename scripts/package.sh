#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

version=${1:-0.0.0}
if [[ ! "$version" =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]]; then
  echo "Expected a version in X.Y.Z format" >&2
  exit 1
fi

stage=$(mktemp -d)
trap 'rm -rf "$stage"' EXIT
app="$stage/Quota Rail.app"
contents="$app/Contents"
resources="$contents/Resources"
output=${QUOTA_RAIL_OUTPUT_DIR:-dist}
mkdir -p "$contents/MacOS" "$resources" "$output"
plist="$contents/Info.plist"
executable=quota-rail
cat > "$plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "https://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key><string>com.cododel.quota-rail</string>
  <key>CFBundleName</key><string>Quota Rail</string>
  <key>CFBundleIconFile</key><string>QuotaRail</string>
  <key>CFBundleExecutable</key><string>$executable</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$version</string>
  <key>CFBundleVersion</key><string>$version</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
</dict>
</plist>
PLIST

swift_flags=()
if [[ "$version" != 0.0.0 ]]; then
  key=${SPARKLE_PUBLIC_KEY:?Set SPARKLE_PUBLIC_KEY to the release public key}
  [[ "$key" =~ ^[A-Za-z0-9+/]{43}=$ ]] || { echo "Invalid Sparkle public key" >&2; exit 1; }
  feed_url=${QUOTA_RAIL_FEED_URL:-https://github.com/cododel/quota-rail/releases/download/update-feed/appcast.xml}
  [[ "$feed_url" == https://* ]] || { echo "The appcast requires HTTPS" >&2; exit 1; }
  sparkle=${QUOTA_RAIL_SPARKLE_DIR:-"$stage/sparkle"}
  if [[ -z "${QUOTA_RAIL_SPARKLE_DIR:-}" ]]; then bash scripts/fetch-sparkle.sh "$sparkle"; fi
  mkdir -p "$contents/Frameworks"
  ditto "$sparkle/Sparkle.framework" "$contents/Frameworks/Sparkle.framework"
  cp "$sparkle/LICENSE" "$resources/Sparkle-LICENSE"
  swift_flags=(-D QUOTA_SPARKLE -F "$contents/Frameworks" -framework Sparkle
    -Xlinker -rpath -Xlinker '@executable_path/../Frameworks')
  if [[ -z "${QUOTA_RAIL_FEED_URL:-}" ]]; then swift_flags+=(-D QUOTA_RELEASE); fi
  /usr/libexec/PlistBuddy -c "Add :SUFeedURL string $feed_url" -c "Add :SUPublicEDKey string $key" \
    -c 'Add :SUVerifyUpdateBeforeExtraction bool true' -c 'Add :SURequireSignedFeed bool true' \
    -c 'Add :SUEnableAutomaticChecks bool true' -c 'Add :SUAllowsAutomaticUpdates bool false' "$plist"
fi

xcrun --sdk macosx swiftc -O -parse-as-library \
  -target arm64-apple-macosx14.0 -module-cache-path cache \
  ${swift_flags[@]+"${swift_flags[@]}"} Sources/*/*.swift -o "$contents/MacOS/$executable"
mkdir -p "$resources/assets"
cp assets/{claude.png,antigravity.png,grok.svg,opencode.svg,kimi.svg,gpt.png} "$resources/assets/"
cp assets/QuotaRail.icns "$resources/QuotaRail.icns"
codesign --force --deep --sign - "$app"
codesign --verify --deep --strict "$app"
ditto -c -k --norsrc --noextattr --keepParent "$app" "$stage/quota-rail-macos-arm64.zip"
mv "$stage/quota-rail-macos-arm64.zip" "$output/"
