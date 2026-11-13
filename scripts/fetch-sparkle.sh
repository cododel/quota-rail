#!/bin/bash
set -euo pipefail

destination=${1:?Expected a Sparkle destination}
version=2.9.0
sha256=01e0f0ebf6614061ea816d414de50f937d64ffa6822ad572243031ca3676fe19
archive=$(mktemp)
trap 'rm -f "$archive"' EXIT

curl --fail --silent --show-error --location --max-time 120 --retry 2 \
  "https://github.com/sparkle-project/Sparkle/releases/download/$version/Sparkle-$version.tar.xz" -o "$archive"
printf '%s  %s\n' "$sha256" "$archive" | shasum -a 256 -c -
mkdir -p "$destination"
tar -xf "$archive" -C "$destination"
