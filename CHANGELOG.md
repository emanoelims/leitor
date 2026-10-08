# Changelog

Versions follow [SemVer](https://semver.org/). Maintainers record user-visible
changes and migration instructions before each release. Use the categories
Added, Changed, Deprecated, Removed, Fixed, and Security as applicable; omit empty
categories. Entries are curated manually and are not generated from Git history.

## [Unreleased]

### Added

- Public sentence reading and document/photo import, private saved texts, vocabulary
  and expressions, spaced review, writing feedback, and persisted lesson guides.
- Dictation, local shadowing recordings, paraphrase practice, and activity-based progress.
- Private shared reading rooms with Presence, host navigation, and temporary chat.
- ReqLLM structured Anthropic tutoring with recoverable errors and configurable models.
- Reusable Phoenix function components, a development gallery, and the approved
  reading interface with responsive layouts, keyboard controls, and a dark theme.

- Phoenix LiveView authentication with Argon2 password hashing, email magic links,
  account settings, session management, and generated tests.

- Contribution guidelines, Conventional Commits, and release policy.
- CI for formatting, compilation, tests, PR titles, and release tag versions.
- Mise tool configuration and tasks shared with CI.
- Credo and Dialyzer analysis, Styler formatting, Doctor documentation checks,
  ExDoc developer documentation, and executable account examples.
- Authentication contract register and an 83 percent line coverage floor.
- Weekly Dependabot updates, issue forms, expanded PR guidance, and private
  vulnerability reporting with a security policy.
- CI dependency auditing, documentation and coverage gates, immutable Action
  references, job timeouts, and cancellation of obsolete runs.

### Changed

- Browser authentication uses email magic links exclusively, including first-time sign-up.
- New application identities use native Ecto UUID v7; existing identities are preserved.
- Custom Tailwind/CSS components replace daisyUI.

- Elixir 1.20.4 built for OTP 29, with Erlang updates limited to the 29 series.
