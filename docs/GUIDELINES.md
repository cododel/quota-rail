# Product and engineering guidelines

These are the accepted Quota Rail behaviors to preserve. They describe the product,
not a claim that every scenario has been tested. Development evidence and superseded
experiments are summarized in [the session review](DEVELOPMENT_REVIEW.md).

## Native, unobtrusive interaction

- Quota Rail is a standalone Swift/AppKit/SwiftUI overlay at the right screen edge.
  It remains available across macOS Spaces, including fullscreen application spaces.
- Hover reveals the panel; clicking a subscription opens its details rather than
  enlarging the rail again. An open popover or the keep-visible setting holds it open.
- The collapsed activation region is 3 pt wide by 48 pt high. Check actual pointer
  coordinates: changing a clipping or content shape alone is not sufficient evidence
  that the activation region changed. Expanded interaction includes the whole panel.
- A second click on the active ring or gear closes its popover exactly once, without
  blinking or reopening. Outside clicks, including clicks in another application,
  close details and settings. Clicks inside the popover remain usable; Escape closes it.
- Give dismissal a single state owner. A nonactivating panel cannot rely on application
  blur alone. Avoid an outside-dismiss handler and a button toggle both handling the
  same anchor click as independent state changes.
- Measure finite, bounded popover content before positioning. Show the native window
  outside the SwiftUI layout update. Anchor the arrow to the selected ring or gear,
  independently of animated row offsets. Constrain the entire settings content, not
  just its subscription list, so flexible dividers cannot expand it to screen width.

## Geometry and visual hierarchy

- Dimensions are macOS logical points, not Retina backing pixels. Keep the expanded
  rail 40 pt wide. Balance space around each ring and its percentage as one group.
- Preserve the smoothly joined silhouette. The settings arc and disk share the center
  of the lower concave bend. A precise drawing must derive from the rendered geometry;
  generated reference images are visual studies, not measurement authorities.
- Use recognizable provider logos without background tiles. Match their optical size
  and weight; equal bounding boxes do not ensure equal apparent size. Codex uses the
  GPT mark; Antigravity has its own mark rather than Gemini's.
- Additional visible subscriptions extend the rail vertically without shrinking rings
  or tightening spacing. Preserve support for all six current connectors. Before
  adding more, verify window bounds and settings access; do not assume unbounded capacity.
- Low background contrast adds a 1 pt light-gray outline: panel opacity 20%, settings
  arc and disk opacity 15%. Keep contrast diagnostics out of normal settings. Any
  screen-access request must explain adaptive outlines, not imply quota measurement.

## Motion

- `OverlayMotion.swift` owns the shared curve and duration presets. The accepted curve
  is `cubic-bezier(0.22, 0, 0.18, 1)`. Reuse its named transitions rather than introducing
  unrelated springs or easing constants in views.
- At startup, a 6 × 6 pt dot begins beyond the screen edge, emerges 3 pt onto the screen,
  then morphs into the compact island (approximately 24 pt high). Hover becomes active
  after entrance finishes. The current entrance phases are 420 ms and 580 ms.
- Animate the contour and coordinated content movement. Do not scale the whole rail
  and its rings, or reveal otherwise stationary rings solely with a mask. Rings retain
  full size and move into place, clipped by the animated contour, without a ring fade.
- At rest, settings is a radial arc fitted to the lower bend. Hover grows it into the
  disk. Scale the gear with the disk and use a short fade so it does not become a tiny
  static glyph inside a growing circle.
- Settings hover/click is enabled only after the rail fully expands, and disabled as
  soon as collapse starts. Apply the 50 ms settings-hover delay only then; cancel it
  when the pointer leaves. Obsolete animation completions must not re-enable controls.
- Respect Reduce Motion while preserving final geometry and interaction availability.

## Subscription truth and discovery

- Keep CLI installation, account authorization, subscription/plan and quota availability
  separate. A binary is not a subscription; a successful login is not a quota response;
  empty quota data does not prove that the account has no subscription.
- Reuse existing CLI sign-ins. Discovery must account for GUI launches without the
  interactive shell's PATH. Provider helpers must have bounded execution and clean up
  their own processes on completion, failure and cancellation.
- Read structured quota data; do not estimate subscription limits from token counts.
  Preserve returned windows, groups and reset times. Unknown plans stay unknown.
  Invalid or unavailable data must not become a fabricated percentage.
- In normal mode, settings lists only installed CLIs with a recognized signed-in account.
  Each row has a checkbox and name on the left, a known plan on the right. Without
  quota, disable the checkbox and show `No quota`; do not remove the account row.
- Only enabled subscriptions with valid quota appear as rings. Persist visibility
  choices. Settings remain reachable when all subscriptions are hidden or unavailable.
- Details are dense, with restrained typography and width. The ring already emphasizes
  remaining quota; do not add a large duplicate hero percentage. Keep date and time
  together, display all available quota windows, and use a list for banked-reset expiries.
  Show credits only when supported; mark dollar conversions as approximate.
- Antigravity is one subscription with Gemini and Claude/GPT groups, each with 5h and
  7d windows. Direct Claude and Codex subscriptions stay separate. Grok Build shows
  the shared weekly pool. OpenCode Go and Kimi retain the windows their APIs report.

## Demo and development

| Launch mode | Data and controls |
| --- | --- |
| No demo flags | Real quotas only; no mock fallback; ignore stored demo preference |
| `--demo` | Enables the `Full demo mode` setting; live data while off, all mocks while on |
| `--full-demo` | Force all connector mocks; hide the toggle; takes precedence over `--demo` |

- Full demo always includes every implemented connector, independent of saved live
  visibility. Switching back must preserve live preferences. Do not add per-row Demo
  badges; the launch mode owns this distinction.
- Demo windows and fields should reflect the provider being represented. Antigravity
  has no mock banked resets or invented credit balance. The explicitly requested single
  Claude banked reset is a UI fixture, not evidence of a supported live API capability.
- `watch-preview` rebuilds on source changes and replaces its own child only after a
  successful build. A failed build leaves the last working process running. This is
  build-and-restart, not in-process hot reload.
- In the terminal, `d` switches live/full demo and `r` restarts the last successful
  build without compiling. Ctrl+C stops the watcher and its child.

## Application lifecycle and distribution

- Keep bundle identity `com.cododel.quota-rail` stable. Bundle helpers and assets in the
  `.app`; preserve adjacent-to-executable resources for source development. Migrate
  legacy `projector-overlay` preferences without overwriting existing app preferences.
- On the first eligible release launch, register for Open at Login. Do not re-enable it
  after the user disables it. Failed registration must remain diagnosable and retryable;
  a missing registration is not a reason to skip the registration attempt. Development,
  demo and ordinary test builds must not register. Quit terminates the app without
  removing the user's login-item choice.
- Release updates use pinned Sparkle, startup checks and **Check for Updates**, with
  user confirmation before installation. Source/watch and untagged CI builds do not
  check for updates or offer an older public release as an upgrade.
- Distribute an ad-hoc signed `.app` in `quota-rail-macos-arm64.zip`. Do not claim Developer
  ID signing or notarization. Require Sparkle EdDSA verification for appcast and archive,
  including archive verification before extraction. Keep private keys outside the repo
  and expose them only to signing.
- The stable feed lives in the mutable `update-feed` prerelease. Publish only stable
  versions with a ready archive: verify the public ZIP against the signed file before
  advancing the feed, then verify the public feed. Stop on failure; retry against the
  already published archive. Publication remains a separately authorized operation.

## Acceptance scenarios

Run applicable fixture checks/builds and arrange operator/CI verification for affected
interactive scenarios. These are acceptance anchors, not claims of past coverage.

| Change | Check |
| --- | --- |
| Hover/motion | Approach inside/outside 3 pt strip; entrance sequence; fast enter/leave; gear during expansion; Reduce Motion |
| Popovers | Ring and gear repeat click; no blink/reopen; outside-app click; inside interaction; Escape; arrow position and bounded width |
| Layout | Zero, one, three and all six rings; all hidden; light/dark backgrounds; consistent logo weight; Spaces/fullscreen |
| Providers | Missing CLI; missing/expired login; unknown plan; empty/malformed response; valid windows; packaged helper lookup |
| Demo/watcher | Both flags and no flag; stored preference isolation; all connectors; d/r; failed compile retains child; cleanup |
| Login item | Exact installed build; registration status/logs; failure retry; user-disabled choice; actual sign-out/sign-in separately |
| Updates | Isolated signed version pair; install/relaunch; preferences/resources retained; up-to-date; cancel; unavailable/corrupt ZIP; bad feed signature; unwritable destination |

An update failure must leave the current app usable. Local test-pair success does not
establish public feed readiness. See README for packaging and release setup.
