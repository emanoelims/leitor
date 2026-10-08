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

## Optional Tidewave MCP

Tidewave is available inside the Phoenix development server only in development.
Each contributor configures their own MCP client; the repository does not ship
an MCP registration or modify global client settings.

Start Phoenix with `mise run dev`. The default endpoint is
`http://localhost:8080/tidewave/mcp`. To connect Codex globally, optionally run:

```sh
codex mcp add tidewave --url http://localhost:8080/tidewave/mcp
```

To use another port, set `PORT` in the ignored `mise.local.toml` and configure
your MCP client with the same port:

```toml
[env]
PORT = "8081"
```

Check the effective port with `mise exec -- printenv PORT`. A local `PORT`
entry overrides an exported value; remove the entry to use `export PORT=...`
instead. Restart Phoenix after changing its port and update your personal MCP
registration separately. A running desktop client does not automatically inherit
the mise environment or update a saved URL.

`AGENTS.md` describes how to use Tidewave when connected. Runtime tools use the
development app and database and complement the test and quality checks.

See the [Tidewave MCP guide](https://tidewave.hexdocs.pm/mcp.md) for connection
troubleshooting and the optional proxy for worktrees running on different ports.
