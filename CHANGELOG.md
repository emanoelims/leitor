# Changelog

Versions follow [SemVer](https://semver.org/). Entries are curated manually.

## [Unreleased]

### Added

- A Dictionary action in the selection toolbar. Its answer opens in the same
  margin card as Define and Explain: IPA, inflected forms, and Brazilian
  Portuguese translations grouped by sense from a local import of English
  Wiktionary (kaikki.org), with the meaning in the current passage chosen by a
  contextual DeepL translation and optional bilingual examples from Azure
  Translator. The card keeps its meaning and part of speech for word jars.
- `mix leitor.dictionary.import` and `Leitor.Release.import_dictionary/1` load
  the dictionary. Configure `DEEPL_API_KEY`, `AZURE_TRANSLATOR_KEY`, and
  `AZURE_TRANSLATOR_REGION` to enable the optional services.

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
