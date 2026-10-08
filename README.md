# Leitor

Install [mise](https://mise.jdx.dev/getting-started.html) and make PostgreSQL
available on `localhost:5432` with the development credentials configured in
`config/dev.exs`. Use your preferred PostgreSQL setup.

From the project directory, install the tools and start Phoenix:

```sh
mise install
mise run setup
mise run dev
```

Visit [`localhost:8080`](http://localhost:8080), or the port configured in
`mise.local.toml`. Mise uses Elixir `1.20.4-otp-29` and Erlang/OTP `29`.

Run `mise run precommit` before submitting changes. It checks compilation,
dependencies, formatting with Styler and the HEEx formatter, strict Credo analysis,
Doctor, documentation generation, Dialyzer, and tests (including doctests).
The first Dialyzer run builds a cache and can take several minutes.

Generate developer documentation with `mise exec -- mix docs --warnings-as-errors`
and open `doc/index.html`. Run `mise exec -- mix test --cover --warnings-as-errors`
for the line coverage report in `cover/`.

## Authentication

Register at `/users/register` and open `/dev/mailbox` to view development emails.
Authentication supports email magic links and passwords hashed with Argon2.
Set a password from `/users/settings` after confirming your account.

Ready to run in production? Please [check our deployment guides](https://phoenix.hexdocs.pm/deployment.html).

## Learn more

* Official website: https://www.phoenixframework.org/
* Guides: https://phoenix.hexdocs.pm/overview.html
* Docs: https://phoenix.hexdocs.pm
* Forum: https://elixirforum.com/c/phoenix-forum
* Source: https://github.com/phoenixframework/phoenix

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for PR rules, Conventional Commits,
semantic versioning, domain typespecs, documentation and doctest patterns, and
Elixir/Phoenix checks. The [authentication contracts](guides/authentication-contracts.md)
connect current behavior to its test evidence and document its limits.

Report vulnerabilities privately as described in [SECURITY.md](SECURITY.md).

## Local Tidewave MCP

Tidewave runs inside the Phoenix development server and is enabled only in
development. The project MCP configuration is `.mcp.json`. Its URL uses
`${PORT:-8080}`: clients supporting this syntax read `PORT` from their
inherited environment, falling back to `8080`.

Mise supplies the same `PORT` to Phoenix through `config/runtime.exs`.
Start the server with `mise run dev`. In another terminal, start a compatible
MCP client from this directory with mise, for example:

```sh
mise exec -- claude
```

To use another port, set `PORT` in the ignored `mise.local.toml`:

```toml
[env]
PORT = "4010"
```

Restart both Phoenix and the MCP client after changing the port. An already
running desktop client does not automatically inherit the mise environment.
The client must support project `.mcp.json` files and URL variable expansion;
this file alone does not register a server globally in Codex.

For Codex, register Tidewave globally using the effective mise environment:

```sh
mise run mcp:register
```

This stores a resolved URL in Codex's global configuration, currently
`http://localhost:8080/tidewave/mcp` with the default port. The shell expands
`PORT` when registration runs; the saved URL does not change automatically.
After changing the effective port, restart Phoenix, run
`mise run mcp:register` again, and reconnect or restart the Codex client.
Mise supplies variables to commands it launches; it cannot update the environment
of an already running desktop client. A local `PORT` setting overrides the
project default and overrides an exported value. To use `export PORT=...`,
remove the local `PORT` entry first; the project default only applies when
`PORT` is unset. Check the effective port with `mise exec -- printenv PORT`
before registering.

`AGENTS.md` describes when to use Tidewave's runtime evaluation, installed docs,
source lookup, logs, SQL inspection, browser automation, and design canvas.
Browser tools need a connected browser; follow their help and connection guidance,
including opening `/tidewave` when requested. Runtime tools use the development
app and database. They complement the test and quality checks.

See the [Tidewave MCP guide](https://tidewave.hexdocs.pm/mcp.md) for connection
troubleshooting and the optional proxy for worktrees running on different ports.
