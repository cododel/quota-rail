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
  gh release create "$tag" "$directory/$archive" --repo "$repo" --verify-tag --generate-notes
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
for attempt in 1 2 3 4 5; do
  if curl -fsSL --max-time 30 "$feed_url" -o "$stage/published.xml" &&
     cmp -s "$stage/published.xml" "$directory/appcast.xml"; then
    exit 0
  fi
  sleep 3
done
echo "Published feed could not be verified. Retry publication for $tag." >&2
exit 1
