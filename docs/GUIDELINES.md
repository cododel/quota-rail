# Product and engineering guidelines

These are the accepted Quota Rail behaviors to preserve. They describe the product,
not a claim that every scenario has been tested. Development evidence and superseded
experiments are summarized in [the session review](DEVELOPMENT_REVIEW.md).

## Design ownership and implementation safeguards

[DESIGN.md](DESIGN.md) owns the concept, geometry, color palette, motion, typography,
component states and visual acceptance criteria. Keep design changes there rather than
copying tokens into this document. The following safeguards protect those interactions:

- Check actual pointer coordinates; clipping or content shape changes alone do not prove
  that the hover activation region changed.
- Give popover dismissal one state owner. A nonactivating panel cannot rely on app blur
  alone; outside-dismiss and anchor-toggle handlers must not independently invert state.
- Measure finite, bounded content before positioning, and present the native window
  outside the SwiftUI layout update. Constrain the whole settings content, not just its list.
- Reuse shared geometry, palette and motion owners. Cancel stale hover tasks and ignore
  obsolete animation completions so controls cannot become active after collapse.
- Treat generated reference images as visual studies, not measurement authorities.
  A precise geometry export must derive from the rendered contour.

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
- In normal mode, settings lists all installed supported CLIs. Enabled subscriptions appear
  as rings after a successful quota read. A paid plan is not required. Plan labels do
  not determine eligibility for display. A failed refresh retains the last successful snapshot in memory and marks it
  stale until refreshed. Clear it when the CLI is removed or the provider explicitly
  reports lost authorization or an API-only profile. Persist visibility choices separately.
- Preserve all available quota windows and banked-reset expirations for details. Expose
  credits only when supported, and distinguish an approximate conversion from cash value.
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

- Keep bundle identity `com.cododel.quota-rail` stable. Bundle assets in the
  `.app` and resolve source-development resources from the checkout beside the executable.
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
interactive scenarios. Use the [design review checklist](DESIGN.md#review-checklist)
for UI changes. These are acceptance anchors, not claims of past coverage.

| Change | Check |
| --- | --- |
| Providers | Missing CLI; missing/expired login; unknown plan; empty/malformed response; valid windows; Antigravity status-line callback and CLI cleanup |
| Demo/watcher | Both flags and no flag; stored preference isolation; all connectors; d/r; failed compile retains child; cleanup |
| Login item | Exact installed build; registration status/logs; failure retry; user-disabled choice; actual sign-out/sign-in separately |
| Updates | Isolated signed version pair; install/relaunch; preferences/resources retained; up-to-date; cancel; unavailable/corrupt ZIP; bad feed signature; unwritable destination |

An update failure must leave the current app usable. Local test-pair success does not
establish public feed readiness. See README for packaging and release setup.
