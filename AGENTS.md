# Quota Rail agent guide

Quota Rail is a standalone native macOS application. Read the
[design specification](docs/DESIGN.md) for visual and interaction work and
[engineering guidelines](docs/GUIDELINES.md) before changing behavior. See
[session review](docs/DEVELOPMENT_REVIEW.md) for the development lessons behind these rules.
The [README](README.md) owns installation and development entry points.
Before preparing a release, follow the [release notes guide](docs/RELEASING.md).

## Scope and working copy

- Work in this repository. Do not patch the old temporary Swift demo or integrate with
  Projector unless explicitly requested. There is no Projector submodule requirement.
- Before diagnosing a reported failure, identify the running executable, build mode and
  source checkout. A source build, an installed `.app`, and a ZIP in `dist/` may differ.
- Use `bun run watch-preview` from the repository for native previews. Do not substitute
  a web mockup for verification of macOS layout, pointer events or animation.
- Keep scratch work under an ignored, uniquely named `.tmp/` directory. Do not commit
  transcripts, credentials, account responses, generated binaries or test signing keys.

## Change discipline

- Preserve the accepted behavior in the product guidelines. Screenshots and reference
  projects guide investigation; they do not authorize unrelated product changes.
- Distinguish an operator decision from an agent suggestion. Later explicit corrections
  supersede earlier experiments. Ask only about material unresolved choices.
- Diagnose the actual event/data path before fixing symptoms. For UI issues, trace
  state, layout measurement, coordinate conversion and event ordering together.
- Reuse the existing geometry, motion, popover and resource owners. Avoid separate
  implementations for settings and subscription popovers that can drift apart.
- Keep product text and repository documentation in English. Keep status explanations
  concise and user-facing; internal diagnostics do not belong in the normal settings UI.
- Research provider logic against installed CLI behavior and versioned primary sources.
  CanvasTTY is an implementation reference, not a guarantee of protocol stability or
  permission to invent fields. Record asset provenance in `assets/SOURCES.txt`.
- Do not add dependencies without agreement. Use existing sign-ins only within the
  authorized task; never print tokens or commit private account data. Do not generate
  paid model requests merely to test quota discovery.

## Verification and handoff

- Run checks proportional to the change. Use the compile/build commands in README and
  the exact fixture-check source list in `.github/workflows/macos.yml`; do not treat
  `checks/agy-quota-probe.py` as an offline fixture test.
- Extend parser checks for changed formats and empty/error responses. Use fabricated,
  sanitized fixtures. Preserve existing successful cases.
- For geometry and interaction work, provide the operator with the affected scenarios
  from `docs/DESIGN.md`. Do not run local automated E2E tests; leave E2E to the
  operator or existing CI. Compilation is not visual acceptance.
- Report separately: static checks, build, fixture tests, live provider reads, observed
  UI behavior and operator confirmation. A failed UI tool is a verification gap, not a pass.
- For perceived low FPS, distinguish dropped frames from mismatched component motion.
  Do not claim a performance cause or improvement without corresponding evidence.
- When packaging matters, check the packaged resources and installed executable, not
  only the loose binary. Label test builds and state which release features are enabled.
- Stop task-owned helper processes and test servers before handoff unless asked to keep
  them running. Never terminate unrelated CLI sessions or watchers.
- Review the final diff. Commit only when requested in this primary checkout, grouping
  changes by meaning and staging only owned paths/hunks. Report the commit SHA.
  A commit request does not authorize a push, tag, release or appcast publication.

## Code navigation

| Responsibility | Owner |
| --- | --- |
| Panel, view state, hover, settings, quota refresh orchestration | `main.swift` |
| Contour dimensions and drawing export | `OverlayGeometry.swift` and `EdgeShape` in `main.swift` |
| Shared animation curve and durations | `OverlayMotion.swift` |
| Remaining-quota colors and soft thresholds | `QuotaPalette.swift` |
| Popover measurement, anchoring and dismissal | `IndicatorPopover.swift` (`RailPopover`) |
| Installation/account/plan/quota status | `ProviderStatus.swift` |
| Live/demo subscription composition | `OverlaySubscription.swift` |
| Provider protocols | `*Quota.swift`, `agy-quota.py`, `claude-quota.py` |
| Resource location and legacy preferences | `AppResources.swift` |
| Updates and launch at login | `ReleaseUpdates.swift`, `LoginItem.swift` |
| Watcher, packaging and publication | `watch.mjs`, `scripts/`, `.github/workflows/macos.yml` |
