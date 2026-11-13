#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

version=${1:-0.0.0}
if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "Expected a version in X.Y.Z format" >&2
  exit 1
fi

stage=$(mktemp -d)
trap 'rm -rf "$stage"' EXIT
bundle="$stage/Quota Rail"
mkdir -p "$bundle" dist
xcrun --sdk macosx swiftc -O -parse-as-library \
  -target arm64-apple-macosx14.0 -module-cache-path cache \
  *.swift -o "$bundle/projector-overlay"
cp agy-quota.py claude-quota.py "$bundle/"
cp -R assets "$bundle/"
printf '%s\n' "$version" > "$bundle/VERSION"
ditto -c -k --norsrc --noextattr --keepParent "$bundle" "$stage/quota-rail-macos-arm64.zip"
mv "$stage/quota-rail-macos-arm64.zip" dist/
