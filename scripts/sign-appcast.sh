#!/bin/bash
set -euo pipefail
directory=${1:?Expected directory containing release ZIP}
tag=${2:?Expected release tag}
signer=${3:?Expected Sparkle tools directory}
: "${SPARKLE_PRIVATE_KEY:?Set SPARKLE_PRIVATE_KEY}"
: "${SPARKLE_PUBLIC_KEY:?Set SPARKLE_PUBLIC_KEY}"
archive="$directory/quota-rail-macos-arm64.zip"
stage=$(mktemp -d)
trap 'rm -rf "$stage"' EXIT
ditto -x -k "$archive" "$stage"
plist="$stage/Quota Rail.app/Contents/Info.plist"
codesign --verify --deep --strict "$stage/Quota Rail.app"
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$plist")" == "${tag#v}" ]]
[[ "$(/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' "$plist")" == "$SPARKLE_PUBLIC_KEY" ]]
[[ "$(/usr/libexec/PlistBuddy -c 'Print :SUFeedURL' "$plist")" == "https://github.com/${GITHUB_REPOSITORY}/releases/download/update-feed/appcast.xml" ]]

# Derive the public key without passing the private seed as a process argument.
public_key=$(printf '%s' "$SPARKLE_PRIVATE_KEY" | xcrun swift -module-cache-path "$stage/cache" -e '
import CryptoKit
import Foundation
guard let line = readLine(), let seed = Data(base64Encoded: line), seed.count == 32 else { exit(1) }
let key = try Curve25519.Signing.PrivateKey(rawRepresentation: seed)
print(key.publicKey.rawRepresentation.base64EncodedString())
')
[[ "$public_key" == "$SPARKLE_PUBLIC_KEY" ]] || { echo "Sparkle signing keys do not match" >&2; exit 1; }

printf '%s\n' "$SPARKLE_PRIVATE_KEY" | "$signer/generate_appcast" --ed-key-file - \
  --maximum-deltas 0 --download-url-prefix "https://github.com/$GITHUB_REPOSITORY/releases/download/$tag/" "$directory"
printf '%s\n' "$SPARKLE_PRIVATE_KEY" | "$signer/sign_update" --ed-key-file - --verify "$directory/appcast.xml"
signature=$(python3 - "$directory/appcast.xml" "$tag" <<'PY'
import sys
import xml.etree.ElementTree as ET

root = ET.parse(sys.argv[1]).getroot()
enclosures = root.findall("./channel/item/enclosure")
if len(enclosures) != 1:
    sys.exit("Expected exactly one signed archive")
enclosure = enclosures[0]
if not enclosure.get("url", "").endswith(f"/{sys.argv[2]}/quota-rail-macos-arm64.zip"):
    sys.exit("Unexpected archive URL in appcast")
print(enclosure.attrib["{http://www.andymatuschak.org/xml-namespaces/sparkle}edSignature"])
PY
)
printf '%s\n' "$SPARKLE_PRIVATE_KEY" | "$signer/sign_update" --ed-key-file - --verify "$archive" "$signature"
