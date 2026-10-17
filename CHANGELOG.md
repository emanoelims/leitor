# Changelog

Versions follow [SemVer](https://semver.org/). Entries are curated manually.

## [Unreleased]

## [0.3.1] - 2026-10-17

### Fixed

- Use OverlayFS for the private checker's disposable container layers instead
  of copying the full Chromium filesystem for every check. Keep the existing
  isolation, resource ceilings and execution deadlines.
- Record bounded checker completion/failure timings without source, credentials
  or provider data, improving production execution diagnostics.

## [0.3.0] - 2026-10-17

### Added

- An original program-authoring loop with streamed source, isolated compilation
  and browser experiments, screenshot-based review and bounded repair attempts.
  Reviewed programs use private immutable artifacts and opaque sandboxed reader
  frames; failed proposals remain non-executable drafts. A separate private Fly
  checker deploys before Phoenix after each stable GitHub release.
- Durable account-owned generation recovery after browser disconnects, including
  completed results without another paid request, and in-editor AI adjustments
  that preserve the original figure until a new revision passes review.
- Immutable mechanical and interaction contracts across bounded coding stages,
  saved recovery and automatic repairs; mandatory observed motion prevents
  decorative play controls from passing the execution gate.
- A fresh mobile-default framing gate that rejects SVG clipping even when HTML
  overflow is hidden, preserving separate optional inspection views.
- An unchanged automatically authored rack-and-pinion regression with 22 model
  checks, five UI experiments, contact inspection and real bounded motion.
- A versioned interactive-figure engine built on the MIT-licensed Anatomy drawing
  kit, with freely authored solid compositions, assembly opening, camera controls,
  part inspection, and a backwards-compatible workbench with live queue simulation and individual station
  controls, counters, manual stepping, themes and reduced-motion support.
- Validated portable figure blueprints generated with Claude and saved in page
  Markdown. Additional creative generation formats are marked as coming soon;
  existing SVG and animated-scene pages remain readable and editable.
- MIT project license and retained third-party kit attribution.
- Encrypted account provider keys, personal Claude model selection, and saved
  settings for future image and narration providers, including ElevenLabs.
- Server-enforced shared Haiku access, daily account/global credit allowances,
  personal-key resource limits, and transactional concurrency reservations.

### Security

- Bind encrypted provider keys to account and provider with AES-256-GCM, omit
  secrets from returned metadata, clear submitted key fields, and require recent
  email authentication for key changes. Shared execution ignores browser model
  overrides. SVG blocks reject scripts, HTML, external references, and arbitrary
  animation code.

## [0.2.1] - 2026-10-16

### Fixed

- Increase the Fly machine to 1 GB so the first streamed explanation has room
  for provider initialization alongside the reader and native highlighting
  runtime. The 512 MB machine was killed by the operating system during use.
- Include the SCTP runtime library required by the Erlang build, removing the
  missing `libsctp.so.1` startup warning.

## [0.2.0] - 2026-10-15

First published release of the page-based reading workspace.

### Added

- Freeform Markdown pages with a block editor, slash commands, automatic import
  titles, PDF extraction, and Claude generation streamed directly into the text.
- Full-text reading with selection actions, contextual explanations, definitions,
  persistent follow-up conversations, paragraph citations, and margin cards.
- Global and per-page notebooks, vocabulary jars, search, and filters.
- Custom themes, reading fonts, typography controls, a document minimap, and
  configurable paragraph numbers inspired by the Gloss reading experience.
- Portuguese and English interfaces through Gettext, independent AI response
  languages, and separate Claude model preferences for reading and writing.
- Lumis syntax highlighting through MDEx with bundled language parsers.
- Fly production release images, isolated database access, Resend authentication
  email, readiness checks, and deployment after stable GitHub releases pass CI.
- Contribution, authentication, deployment, security, and release documentation;
  pinned CI Actions, dependency audits, static analysis, and coverage checks.

### Changed

- Email magic links are the only browser authentication method. Password domain
  APIs and stored legacy hashes remain available internally.
- Pages and the combined notes/vocabulary notebook form the product navigation.
  Retired lesson, practice, review, and collaboration screens have no routes;
  their persisted data and domain ownership rules are preserved.
- Custom components replace daisyUI and share consistent floating menus.
- New identities use Ecto UUID v7; existing identities are preserved.

### Fixed

- Notebook tests accept PostgreSQL locale-dependent title ordering while checking
  the complete owned source set.

### Migration

All pending Ecto migrations run before a Fly rollout. The first deployment uses
an empty, separate `leitor` database on the existing personal Postgres app; local
development data is not uploaded. Configure the secrets in the deployment guide
before publishing a release. Existing installations should back up their database
before applying the accumulated migrations.
