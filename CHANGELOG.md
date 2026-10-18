# Changelog

Versions follow [SemVer](https://semver.org/). Entries are curated manually.

## [Unreleased]

### Fixed

- Dictionary lookups no longer force a reasoning effort. With the shared Haiku
  model the provider rejected the translated `thinking.type.enabled` setting
  (HTTP 400), so every lookup failed; each model now uses its default thinking.

## [0.5.0] - 2026-10-18

### Added

- A Dictionary action in the selection toolbar. Its answer opens in the same
  margin card as Define and Explain. Claude reads the page around the marked
  occurrence and writes the meaning in that context, the headword, IPA, an
  explanation, usage notes, forms, bilingual examples and other senses; the
  meaning streams first. A Brazilian Portuguese pronunciation hint is derived
  from the IPA by rules, prompts reuse cached instructions and page text, and
  finished cards are cached. Lookups use the reader's AI authorization, credits
  and model like other reading help. The card keeps its meaning and part of
  speech for word jars.

### Migration

One additive migration creates `dictionary_cards`, which stores generated cards
by model, prompt version and marked selection. No new secrets are required.

## [0.4.1] - 2026-10-17

### Fixed

- Debit independent figure reviews by measured output usage, retaining the
  conservative allocation when provider counters are unavailable or incomplete.
- Hand expensive first passing renders to independent review earlier, preserving
  repair capacity within the existing token, credit and time limits.
- Improve dark mechanical surface contrast in the shared reader/checker
  environment while preserving light surfaces and explicit authored palettes.
- Guide continued visual repairs to inspect the rejected source and align
  material paths, contact points and section views with model coordinates.

### Validation

The previously rejected steam-driven cane mill passed one normal continuation.
Its unchanged accepted program is retained for isolated regression tests, with
24 model checks, six original UI experiments, motion and mobile framing. The
quality report records both the failed attempt and successful continuation.
No migrations, dependencies, secrets or generation-limit increases are required.

## [0.4.0] - 2026-10-17

### Added

- Scientific-diagram and explanatory-illustration profiles using the same
  isolated authoring, interaction, motion and independent review gates.
- Accepted figure version history with sandboxed previews and free restoration
  of related account-owned versions, preserving surrounding page text.
- An uncharged waiting queue, bounded to one request per account and fifty
  globally, with cancellation, ten-minute expiry and normal authorization
  before dispatch. Running paid work is never automatically repeated.
- Account activity with actual provider token counters, dated cost estimates,
  duration and outcomes; missing and partial measurements remain explicit.
- Six unchanged generated regression programs covering Cardan transmission,
  a cam, governor, ratchet, refraction and lunar phases. The quality report
  preserves initial human findings and the separate paid confirmation.

### Fixed

- Require independent review evidence that explanatory equations and claims
  agree with the actual model and observable readouts.
- Share trusted foreground and color-scheme defaults between the reader and
  checker so inherited text remains readable in dark figures.
- Preserve retry checkpoints when a request waits for capacity, release canceled
  workers' leases, and retry remote admission only after explicit busy rejection.

### Migration

Three additive migrations introduce accepted-revision ancestry, AI measurements
and queued-generation indexes/status. Legacy records remain unmeasured. The
release workflow deploys the updated private checker before migrating and rolling
out Phoenix. No new secrets or provider credentials are required.

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
