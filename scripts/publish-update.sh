#!/bin/bash
set -euo pipefail
tag=${1:?Expected release tag}
directory=${2:?Expected release artifact directory}
repo=${GITHUB_REPOSITORY:?}
archive=quota-rail-macos-arm64.zip
feed_url="https://github.com/$repo/releases/download/update-feed/appcast.xml"
stage=$(mktemp -d)
trap 'rm -rf "$stage"' EXIT

feed=$(gh api "repos/$repo/releases/tags/update-feed")
jq -e '.immutable == false and .prerelease and (.draft | not)' <<< "$feed" >/dev/null || {
  echo "The update-feed release must be a public mutable prerelease." >&2
  exit 1
}

if jq -e '.assets[] | select(.name == "appcast.xml")' <<< "$feed" >/dev/null; then
  curl -fsSL --max-time 60 --retry 2 "$feed_url" -o "$stage/appcast.xml"
  python3 - "$stage/appcast.xml" "${tag#v}" <<'PY'
import sys
import xml.etree.ElementTree as ET

def version(value):
    return tuple(map(int, value.split(".")))

versions = ET.parse(sys.argv[1]).findall(".//{http://www.andymatuschak.org/xml-namespaces/sparkle}version")
if not versions or max(version(node.text) for node in versions) > version(sys.argv[2]):
    sys.exit("Refusing to replace a newer or unreadable update feed.")
PY
fi

if ! gh release view "$tag" --repo "$repo" >/dev/null; then
  notes="docs/releases/$tag.md"
  if [[ ! -s "$notes" ]] || ! grep -q '[^[:space:]]' "$notes"; then
    echo "Missing release notes: $notes. Commit them before tagging $tag." >&2
    exit 1
  fi
  gh release create "$tag" "$directory/$archive" --repo "$repo" --verify-tag --notes-file "$notes"
fi
gh api "repos/$repo/releases/tags/$tag" --jq '.draft == false and .prerelease == false' | grep -qx true
curl -fsSL --max-time 120 --retry 3 "https://github.com/$repo/releases/download/$tag/$archive" -o "$stage/$archive"
cmp "$stage/$archive" "$directory/$archive"

if ! gh release upload update-feed "$directory/appcast.xml" --repo "$repo" --clobber; then
  if [[ -f "$stage/appcast.xml" ]]; then
    gh release upload update-feed "$stage/appcast.xml" --repo "$repo" --clobber
  fi
  exit 1
fi
max_attempts=13
for ((attempt=1; attempt<=max_attempts; attempt++)); do
  if curl -fsSL --max-time 10 "$feed_url" -o "$stage/published.xml"; then
    versions=$(python3 - "$stage/published.xml" <<'PY'
import re
import sys
import xml.etree.ElementTree as ET

try:
    nodes = ET.parse(sys.argv[1]).findall(
        "./channel/item/{http://www.andymatuschak.org/xml-namespaces/sparkle}version"
    )
    versions = [node.text for node in nodes if re.fullmatch(r"[0-9]+(?:\.[0-9]+)*", node.text or "")]
    print(", ".join(versions) or "no readable Sparkle version")
except ET.ParseError:
    print("invalid XML")
PY
)
    echo "Appcast attempt $attempt/$max_attempts: expected ${tag#v}, received $versions."
    if cmp -s "$stage/published.xml" "$directory/appcast.xml"; then
      echo "Public appcast matches the signed file."
      exit 0
    fi
    echo "Public appcast differs from the signed file."
  else
    echo "Appcast attempt $attempt/$max_attempts: download failed (expected ${tag#v})."
  fi
  if (( attempt < max_attempts )); then
    sleep 10
  fi
done
echo "Published feed could not be verified. Retry publication for $tag." >&2
exit 1
