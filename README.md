# Quota Rail

A standalone macOS quota overlay for Codex, Claude, and Antigravity. The overlay uses mock data when provider quotas are unavailable.

On an Apple Silicon Mac with macOS 14 or later and Xcode command line tools:

```sh
xcrun --sdk macosx swiftc -O -parse-as-library \
  -target arm64-apple-macosx14.0 -module-cache-path cache \
  *.swift -o projector-overlay
./projector-overlay --full-demo
```

Run without `--full-demo` to read quotas from installed and authenticated provider CLIs. The Claude and Antigravity helpers use `/usr/bin/python3`. Keep the helpers and `assets/` next to the executable.

For development, `node watch.mjs --full-demo` rebuilds and restarts the overlay when Swift files change.

GitHub Actions builds an Apple Silicon archive for pull requests and pushes to
`main`. Pushing an existing commit as a `vX.Y.Z` tag builds the archive and
publishes it on GitHub Releases.

Download `quota-rail-macos-arm64.zip`, extract the folder, and run
`./projector-overlay` from that folder. The archive is not notarized.

Quota Rail checks the latest published GitHub release, including pre-releases at startup. The settings
popover also has **Check for Updates**. When a newer archive is available,
**Download Update** opens the download in your browser. Quit the old overlay,
extract the archive, and launch the new executable from the extracted folder.
