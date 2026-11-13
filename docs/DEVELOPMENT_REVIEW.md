# Development session review

This review covers the development conversation through commit `525e43d`, from the
initial Swift-helper exploration to the shared entrance animation. It was derived from
user messages and assistant commentary/final replies in the session journal, excluding
tool calls/results, internal reasoning and compaction summaries. Current source and
README were consulted separately to avoid documenting obsolete names or entry points.
Assistant reports below are conversation evidence, not a new execution of their checks.

## What the iterations taught us

| Recurring issue | Lesson captured in the project rules |
| --- | --- |
| Web preview did not establish behavior at the macOS screen edge | Iterate on the native Swift surface for interaction and motion |
| Whole-panel scale, then stationary masked content, felt wrong | Coordinate contour and content movement while preserving ring size |
| Gear looked low-FPS while its glyph stayed fixed in a growing disk | Diagnose perceived motion separately from measured frame drops |
| Rings, icons and padding needed repeated corrections | Preserve agreed width and optical balance; do not equate equal asset dimensions with equal visual weight |
| Native auto-dismiss and button toggles reopened popovers | One owner must resolve the same click; apply the fix to gear and rings together |
| Anchor adjustment did not resolve a displaced popover; premeasurement did | Inspect layout timing as well as coordinates; do not overstate a causal conclusion |
| Deferring popup presentation fixed a crash, but broad measurement expanded settings | Verify the whole affected interaction, including sizing, after a lifecycle fix |
| Narrowing contentShape did not narrow effective hover | Validate pointer coordinates and actual behavior, not only declarative geometry |
| A new adapter existed in one checkout while the user ran another | Establish the executable and checkout before diagnosing provider discovery |
| Installed/logged-in Kimi returned no windows | Separate install, auth, plan and quota rather than collapsing them into “not detected” |
| Grok rejected a string expiry field before querying quota | Verify the installed CLI's schema and protect compatible input variants |
| Default mock fallback concealed missing live data | Keep production truth separate from explicitly selected full demo |
| Local 0.0.0 offered a public 0.0.1 update | Gate release behavior by build identity, not only numeric version comparison |
| Login registration compiled but no item appeared | Verify installed build and system registration; registration still differs from login execution |
| Many changes were only compile-checked before user feedback | State the exact verification boundary and provide concrete interactive scenarios |

## Decisions that superseded earlier experiments

- Standalone Quota Rail replaced the proposed Projector/submodule integration.
- The repository watcher replaced the temporary demo directory as the development entry point.
- Two demo flags and explicit full demo replaced unconditional fallback and older flags.
- Antigravity groups replaced the placeholder Gemini subscription and arbitrary daily window.
- Compact settings rows replaced exposed installation/auth/quota diagnostic blocks.
- Dense details replaced a large duplicate remaining-percentage emphasis.
- Sparkle installation replaced GitHub API download-link updates for new release builds.
- Shared `OverlayMotion` replaced the earlier per-element spring parameters borrowed from
  boring.notch. The reference informed the geometric approach, not a permanent curve requirement.

## Evidence limits to retain

The conversation reports a successful isolated Sparkle 0.0.2 → 0.0.3 install/relaunch
with preferences preserved, signature rejection checks, live reads for several providers,
and login-item registration. The operator confirmed selected visual fixes, including
Grok display, popover placement, the narrow hover region and the final entrance curve.

These do not establish every acceptance case. In particular, do not infer successful
sign-out/sign-in from login-item registration, complete negative updater coverage from
one upgrade, or working paid-account quotas for every provider from parser fixtures.
The session reported Kimi authentication with empty quotas and no live OpenCode Go
subscription verification. Those are historical observations, not permanent account facts.

Research suggestions about caching, stale-data presentation and provider-specific poll
intervals were not a fully agreed refresh policy. Do not promote them into guarantees.
The Claude demo reset/credit fields were UI examples, not verified provider support.

The current rules live in [AGENTS.md](../AGENTS.md), [DESIGN.md](DESIGN.md) and
[GUIDELINES.md](GUIDELINES.md).
This review records their provenance; it is not a second behavior specification or a
release-readiness report. No raw transcript, private account values or machine paths
are needed in repository documentation.
