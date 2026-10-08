# Contributing

Use Elixir `1.20.4-otp-29` and Erlang/OTP `29`, as configured in `mise.toml`.
Elixir is pinned to a specific release built for OTP 29. Erlang can receive
updates within the 29 series through `mise upgrade erlang`. Update the Elixir
pin explicitly when adopting a new release.

Run `mise install`, then `mise run setup`. Start Phoenix with `mise run dev`.
Before opening a PR, run `mise run precommit`, which executes `mix precommit`.
Mise tasks automatically use the configured tools. For individual commands,
use `mise exec -- mix <task>`. See the
[mise documentation](https://mise.jdx.dev/getting-started.html) for installation
and shell activation.

## Branches and review

Create a branch such as `feat/search`, `fix/reader`, or `docs/setup` and open a
PR against `main`. Contributors need one approval and resolved discussions.
New commits dismiss previous approvals. Deletion and force pushes are blocked
on `main`. Administrators can bypass PR, review, and status check requirements.

Merges use squash: the PR title becomes the commit subject on `main`. Keep the
title up to date and wait for `Conventions` and `Elixir checks` to pass.

## Conventional Commits

Use `<type>[optional scope][!]: <description>` for commit subjects and PR titles.
Allowed types: `feat`, `fix`, `docs`, `style`, `refactor`, `perf`, `test`,
`build`, `ci`, `chore`, and `revert`. Scopes use lowercase letters, numbers,
periods, hyphens, underscores, or slashes. Write descriptions, documentation,
and developer-facing messages in English.

Examples:

- `feat(reader): add search`
- `fix(reader): preserve reading position`
- `ci: validate project conventions`
- `feat(api)!: change response format`

For incompatible changes, use `!` in the PR title and explain the migration
in the body with `BREAKING CHANGE: ...`. This preserves the signal during squash.

## Semantic versioning

The version source is `version` in `mix.exs`, using `MAJOR.MINOR.PATCH`.

- `fix`: increment PATCH, for example `1.2.0` → `1.2.1`.
- Backward-compatible `feat`: increment MINOR, for example `1.2.0` → `1.3.0`.
- Incompatible change: increment MAJOR, for example `1.2.0` → `2.0.0`.
- Other types do not require a release by themselves; assess the public impact.

During `0.x`, the project is experimental. Our policy is to increment MINOR
for features and incompatible changes, and PATCH for fixes. The first release
with a stability commitment will be `1.0.0`.

For a release, open a PR titled `chore(release): prepare X.Y.Z`, update
`mix.exs`, and record changes and migrations in `CHANGELOG.md`. After merging
and passing CI on `main`, create tag `vX.Y.Z` at the corresponding commit.
CI checks that the tag matches `mix.exs` exactly. Prereleases may use
`X.Y.Z-rc.1`. Version increments are reviewed manually; publishing is not automated.

## Elixir and Phoenix

Follow `AGENTS.md`, the formatter configured in `.formatter.exs`, and official
conventions: `CamelCase` modules, `snake_case` functions and variables, predicates
ending in `?`, and functions ending in `!` for raising variants where applicable.
Use Phoenix contexts for business logic and keep it separate from the web layer.
CI requires formatting, compilation without project warnings, no unused lockfile
dependencies, and passing tests. Add analysis tools or dependencies only when
there is a concrete need.

References:

- [Conventional Commits](https://www.conventionalcommits.org/en/v1.0.0/)
- [SemVer 2.0](https://semver.org/)
- [Elixir Version](https://hexdocs.pm/elixir/Version.html)
- [Elixir naming conventions](https://hexdocs.pm/elixir/naming-conventions.html)
- [Elixir library guidelines](https://hexdocs.pm/elixir/library-guidelines.html)
- [Elixir builds in mise](https://mise.jdx.dev/lang/elixir.html)

Library guidelines are a reference; this project is a Phoenix application,
not a package published on Hex.
