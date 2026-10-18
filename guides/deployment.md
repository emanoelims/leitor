# Production deployment

Leitor runs at [leitor.fly.dev](https://leitor.fly.dev) in the Fly `personal`
organization, region `gru`. The app uses one shared CPU and 1 GB of memory.
One machine stays running; this is an initial single-machine deployment.

Allow headroom for the first ReqLLM request: initializing model metadata and the
streaming stack creates a transient memory peak in addition to the reader and
native highlighting runtime. The original 512 MB machine was OOM-killed during
explanation requests; 1 GB must be preserved on subsequent deploys. A passing
idle health check alone does not validate this workload. After deployment, test
a real streamed explanation and confirm that the machine did not restart.

## Publishing

Production deploys only when a **stable GitHub release is published**. Pushing
to `main`, pushing a tag, saving a release draft, and publishing a prerelease
do not deploy. The release workflow reruns the shared CI checks before deploying
the tagged commit, and rejects commits outside `main`. Deploys are serialized.

1. Update `mix.exs` and this release's entry in `CHANGELOG.md`.
2. Run `mise run precommit` and `mise exec -- mix test --cover --warnings-as-errors`.
3. Merge to `main` and wait for `Conventions` and `Elixir checks` to pass.
4. Tag that commit as `vX.Y.Z`; the tag must match `mix.exs`.
5. Publish the GitHub release for that tag. Watch the **Deploy release** workflow.
6. Confirm `/health` returns HTTP 200 and open the login screen.

The workflow builds the Docker image remotely, runs `/app/bin/migrate` in a
temporary release machine, and waits for database-backed readiness checks. A
failed migration blocks the rollout. Migrations are not automatically rolled
back if deployment fails; future schema changes must remain compatible with the
previous release during rollout. Redeploy an earlier compatible image through
the Fly dashboard for emergency recovery, accounting for any applied migrations.

## Database and secrets

The unmanaged Postgres app `sisteo-apps-db` hosts a separate `leitor` database
and non-superuser `leitor` role. The app connects over Fly's private IPv6 network.
This deployment does not copy local development data or modify Sisteo's schema.

When bootstrapping a new attachment with `--superuser=false`, an administrator
must grant the application role `CREATE` on its own database:

```sql
GRANT CREATE ON DATABASE leitor TO leitor;
```

This database-local permission lets the versioned first migration install the
trusted `citext` extension; it does not make the role a superuser. Do not grant
cluster-wide privileges or run schema migrations manually in the SQL console.

Fly secrets:

- `DATABASE_URL`: assigned by the database attachment.
- `SECRET_KEY_BASE`: a separate randomly generated application secret.
- `RESEND_API_KEY`: the authorized Resend credential shared with Sisteo.
- `MAIL_FROM`: the verified email address only, without a display name or brackets.
  The application adds the `Leitor` display name.
- `ANTHROPIC_API_KEY`: the Claude API credential.
- `LEITOR_DICTIONARY_MODEL`: optional model for dictionary cards when the
  reader keeps the default model preference (Claude Sonnet 5.5 if unset).

GitHub's encrypted `FLY_API_TOKEN` secret contains an app-scoped deployment token
for `leitor`, initially valid for one year. Rotate it before expiry with
`fly tokens create deploy --app leitor --expiry 8760h` and replace the GitHub
secret. Never paste its output into logs, release notes, or source files.

The Docker context excludes personal mise overrides, `.env` files, `.sprite`,
temporary files, and Git metadata. Production includes Poppler for PDF imports.
Lumis writes its compiled parser cache to `/tmp/lumis`; user data lives in
Postgres, not the application's ephemeral filesystem.

The public `/health` route has the API pipeline and no browser session. It reports
only readiness and does not expose database details. All product screens retain
the authenticated browser pipeline and LiveView session. Email delivery uses
Resend in production, the local mailbox in development, and Swoosh's test adapter
in tests. Never enable development routes on Fly.
