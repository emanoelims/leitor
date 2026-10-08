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
dependencies, strict Credo checks, Doctor, documentation builds without warnings,
Dialyzer analysis, and passing tests.

`mix format` uses [Styler](https://github.com/adobe/elixir-styler) for Elixir
and `Phoenix.LiveView.HTMLFormatter` for HEEx. Styler automatically organizes
module directives and rewrites code to follow a consistent style. Credo remains
enabled for analysis beyond automatic formatting. Review the resulting diff,
particularly control flow and configuration changes, because some Styler rewrites
can affect behavior. Run `mise run precommit` after formatting. CI verifies the
same formatter output with `mix format --check-formatted`.

## Source map and boundaries

- `lib/leitor/accounts.ex`: account operations and authentication contracts.
- `lib/leitor/accounts/`: account schemas, caller scopes, tokens, and email delivery.
- `lib/leitor_web/user_auth.ex`: browser sessions and authentication hooks.
- `lib/leitor_web/router.ex`: route pipelines and authenticated LiveView sessions.
- `lib/leitor_web/live/user_live/`: registration, login, confirmation, and settings.
- `lib/leitor_web/components/`: shared components and layouts.
- `priv/repo/migrations/`: database changes, generated with `mix ecto.gen.migration`.
- `test/`: behavior tests matching the source layout, with fixtures in `test/support/`.

Keep business rules in contexts, with web modules adapting requests and rendering
results. Do not expose an internal function just to make a test easier. Record
public promises and their evidence in the
[authentication contract register](guides/authentication-contracts.md). Add
resource ownership contracts when resource contexts are introduced.

## Typespecs

Use the [official Elixir typespecs reference](https://elixir.hexdocs.pm/typespecs.html)
as the basis for public domain contracts. Prefer names that explain what a value
means, especially when several parameters share the same primitive type:

```elixir
# Defined in Leitor.Accounts.User:
@typedoc "An email address supplied for account lookup or registration; validation is separate."
@type email() :: String.t()

@typedoc "A plaintext password supplied for authentication; validation is separate."
@type password() :: String.t()

# Used in Leitor.Accounts:
@spec get_user_by_email_and_password(User.email(), User.password()) :: User.t() | nil
```

Define types in the module that owns the concept, reuse them through remote types,
and document public types with `@typedoc`. Use `t()` for a module's main value,
`@typep` for private representations, and `@opaque` when the representation must
be hidden from callers. Avoid aliases that only rename a primitive without adding
domain meaning.

Add accurate `@spec` declarations when creating or changing public domain/context
functions. Include actual success, error, and nullable results. Use named arguments
when helpful, and composed map, struct, tuple, collection, or option types for richer
contracts. For long positional parameter lists, consider a structured input instead
of relying on aliases alone. Framework callbacks and simple private helpers do not
need boilerplate specs just to reach a coverage target.

Aliases such as `email()` and `password()` remain equivalent to `String.t()`;
Dialyzer cannot distinguish these aliases to detect swapped arguments. They do not
guarantee a valid email or password. Enforce invariants with changesets, guards, or
validated constructors, and test those rules.

Elixir 1.20's inferred type system is separate from traditional typespecs. Keep
explicit contracts where they communicate domain intent. Dialyzer is optional for
declaring types, but this project uses it through Dialyxir to find type inconsistencies.
Credo checks readability, consistency, and other code quality issues.

Run all checks with `mise run precommit`. To run the analyzers separately:

```sh
mise exec -- mix credo --strict
mise exec -- mix dialyzer
```

Both analyzers use the test environment, matching CI. The first Dialyzer run builds
a Persistent Lookup Table (PLT) and can take several minutes. Its files live in
the ignored `_build/plts` directory and are included in the CI build cache, keyed
by the BEAM versions and dependency lockfile. Fix findings rather than adding
broad exclusions; document the reason for any narrowly scoped exception.

## Documentation checks and test coverage

Doctor enforces 100 percent function documentation and module documentation,
at least 90 percent specs per module and overall, and types for structs in the
domain scope. `.doctor.exs` lists the excluded Phoenix and infrastructure paths;
these exclusions do not remove those modules from tests or Dialyzer. Current
domain documentation and specs both reach 100 percent. Do not hide public APIs
with `@doc false` or exclude domain modules to satisfy a threshold.

ExDoc builds the README, contribution guide, changelog, contract register, and
module reference. Both tools use the test environment, matching `precommit`.

```sh
mise exec -- mix doctor --summary
mise exec -- mix docs --warnings-as-errors
mise exec -- mix test --cover --warnings-as-errors
```

Open `doc/index.html` for generated documentation and `cover/` for line coverage.
Both directories are ignored. The initial line coverage was approximately 84
percent; the enforced floor is 83 percent, with only test helpers excluded from
the calculation. Domain and web application code remain included. Coverage
does not prove authorization or exhaustively test concurrent behavior: maintain
focused contract tests, and raise the floor as meaningful coverage improves.

## Documentation and executable examples

Follow [Doctests, patterns, and with](https://elixir.hexdocs.pm/docs-tests-and-with.md).
Write documentation in English and keep it close to the code. A module's
`@moduledoc` explains its responsibility and usage; a public domain function's
`@doc` explains observable behavior, options, results, and relevant errors.
Use `@impl` for callbacks. Reserve `@doc false` for intentionally internal public
functions, rather than using it to avoid documenting domain APIs.

Add a `## Examples` section when examples clarify the contract. Prefer small,
realistic, deterministic examples using fully qualified calls or explicit aliases
and setup. Indent executable examples by four spaces, prefix expressions with
`iex>` (and continuations with `...>`), and show the actual expected result.
Separate independent examples with blank lines. Use `@doc ~S"""` to preserve
literal escape sequences such as `\r\n` when needed.

Register executable examples with `doctest Module` in the appropriate ExUnit test
module so `mix test` checks them. `Leitor.Accounts.Scope.for_user/1` and its test
provide a working example. Include meaningful success and failure examples where
appropriate; avoid fake IDs, unbound variables, abbreviated results, and hidden
database prerequisites in executable snippets. Label illustrative, non-executable
snippets as regular code blocks instead of using `iex>` prompts.

Doctests protect documentation accuracy and complement unit and integration tests.
Keep persistence, side effects, validation boundaries, and extensive edge cases in
dedicated tests. Database doctests need `Leitor.DataCase` and explicit setup;
tests involving shared names need unique names and supervised process cleanup.

Use pattern matching and separate function clauses to handle distinct input shapes.
Use descriptive arguments in a shared function head when documenting multiple
clauses. Use `with` for a sequence of dependent operations that can fail, returning
useful non-matching results or translating them explicitly with `else`. Prefer a
simple `case` for one branching operation and a pipeline for straightforward
transformations. Preserve meaningful error distinctions rather than silently
collapsing failures into one generic result.

References:

- [Conventional Commits](https://www.conventionalcommits.org/en/v1.0.0/)
- [SemVer 2.0](https://semver.org/)
- [Elixir Version](https://hexdocs.pm/elixir/Version.html)
- [Elixir naming conventions](https://hexdocs.pm/elixir/naming-conventions.html)
- [Elixir library guidelines](https://hexdocs.pm/elixir/library-guidelines.html)
- [Elixir builds in mise](https://mise.jdx.dev/lang/elixir.html)

Library guidelines are a reference; this project is a Phoenix application,
not a package published on Hex.
