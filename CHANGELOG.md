# Changelog

Versions follow [SemVer](https://semver.org/). Maintainers record user-visible
changes and migration instructions before each release. Use the categories
Added, Changed, Deprecated, Removed, Fixed, and Security as applicable; omit empty
categories. Entries are curated manually and are not generated from Git history.

## [Unreleased]

### Added

- Phoenix LiveView authentication with Argon2 password hashing, email magic links,
  account settings, session management, and generated tests.

- Contribution guidelines, Conventional Commits, and release policy.
- CI for formatting, compilation, tests, PR titles, and release tag versions.
- Mise tool configuration and tasks shared with CI.
- Credo and Dialyzer analysis, Styler formatting, Doctor documentation checks,
  ExDoc developer documentation, and executable account examples.
- Authentication contract register and an 83 percent line coverage floor.

### Changed

- Elixir 1.20.4 built for OTP 29, with Erlang updates limited to the 29 series.
