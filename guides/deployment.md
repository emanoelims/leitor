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
5. Publish the GitHub release for that tag. Watch the **Deploy release** workflow:
   it deploys the private figure checker first, then the public Phoenix app.
6. Confirm both services' health checks pass and open the login screen. Exercise
   a real generation and explanation through an authenticated account.

The workflow builds the Docker image remotely, runs `/app/bin/migrate` in a
temporary release machine, and waits for database-backed readiness checks. A
failed migration blocks the rollout. Migrations are not automatically rolled
back if deployment fails; future schema changes must remain compatible with the
previous release during rollout. Redeploy an earlier compatible image through
the Fly dashboard for emergency recovery, accounting for any applied migrations.

Version 0.4.0 includes three additive migrations for artifact parent references,
AI measurements, and queued-generation indexes/status. Existing attempts remain
unmeasured. No new secrets are required. Queue dispatch runs only in serving
Phoenix instances, not migration or operator CLI processes. Do not interrupt
active paid generations for a routine rollout: check active attempts first and
wait for them to finish. Running work is never automatically replayed after a
restart. The updated checker image includes the shared trusted theme defaults
used by the reader, and must deploy before Phoenix.

Completion telemetry and privacy-preserving timing logs are documented in
[AI usage](ai-usage.md). After deployment, check both streamed explanations and
an isolated figure execution; idle readiness alone does not exercise either.

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

## Account AI budgets and provider keys

All reading and writing UI requests reserve credits in Postgres before starting
the provider call. Without a personal Anthropic key, execution always uses Claude
Haiku, regardless of saved model preferences or server model overrides. A valid
personal key unlocks the supported Claude choices for that account only. Other
provider keys and image/voice model preferences can be saved for future media
integrations; this release renders SVG illustrations and does not call image or
speech APIs. Tidewave's recording narration uses ElevenLabs; it is a separate
development feature, not the application's narration service.

The default daily allowance is 20 shared credits per account and 200 across the
application. Reading costs 1, writing 2, and illustrated generation 4 credits.
Attempts are charged even if the provider fails or the user cancels. Personal
keys use a separate 200-credit daily resource allowance, never shared spending.
Periods reset at 00:00 UTC. One request per account and two globally can run at
once; shared and personal calls both obey concurrency and a two-second cooldown.
Regular leases expire after two minutes so crashed requests do not block indefinitely.
Personal-key illustrations reserve up to 65,536 output tokens including reasoning
and a 20-minute overall execution window, with a 22-minute concurrency lease.
The program author divides that budget across module generation, isolated
execution and independent screenshot review, with at most four coding stages.
Native Opus 5.5 authoring starts at medium effort; a token-truncated edit resumes
at low effort until a complete edit is saved. Thinking cannot be disabled.
Shared illustrations retain Haiku, 6,000 output tokens and the 90-second window.
A bounded generation remains one four-credit attempt; actual provider billing
covers every module and review call. The production program runner operates in
the separate private `leitor-figures` app described below. Never mount a Docker
socket into Phoenix. Browser reconnects reattach to durable attempts without a
second reservation. Server crashes do not automatically repeat paid work;
expired jobs preserve their checkpoints for an explicit bounded retry.
These are request/output bounds, not a currency budget or provider invoice;
configure provider-side spending limits independently when available.

Optional runtime settings (positive integers, except cooldown may be zero):

| Environment | Default |
| --- | --- |
| `AI_DAILY_CREDITS` | 20 |
| `AI_GLOBAL_DAILY_CREDITS` | 200 |
| `AI_PERSONAL_DAILY_CREDITS` | 200 |
| `AI_ACCOUNT_CONCURRENCY` | 1 |
| `AI_GLOBAL_CONCURRENCY` | 2 |
| `AI_COOLDOWN_SECONDS` | 2 |

`AI_ENCRYPTION_SECRET` should be an independent random secret of at least 32
bytes, stored as a Fly secret **before saving the first personal key**. In its
absence the vault derives its encryption key from `SECRET_KEY_BASE`. AES-256-GCM
uses a random nonce and binds ciphertext to account and provider. Back up the
chosen secret with the database. Changing either the independent secret or its
fallback makes existing ciphertext unreadable; rotation needs an explicit
re-encryption migration. Unreadable personal keys fail closed and never silently
charge the shared credential. The UI only returns provider names and final four
characters; saving/removing keys requires an email login within 20 minutes.

## Private figure checker

`figure_service/fly.toml` defines a separate `leitor-figures` app in `personal`,
region `gru`, with two shared CPUs and 4 GB RAM. One Machine stays running to
avoid a cold Docker import consuming a generation deadline. It receives only a
private Flycast IPv6 address; do not allocate public ingress addresses. The
release workflow builds its image from pinned bases and the same tagged kit and
checker sources before deploying Phoenix. Both deployments occur only after a
stable GitHub release is published and its checks pass.

Initial setup (without deploying):

```sh
fly apps create leitor-figures --org personal
fly ips allocate-v6 --private --app leitor-figures
```

Configure an independent random `FIGURE_RUNNER_TOKEN` of at least 32 bytes as a
secret in **both** apps. Set `FIGURE_RUNNER_URL=http://leitor-figures.flycast` in
`leitor`. Stage these secrets with `fly secrets import --stage` to preserve the
release-only deployment policy. The URL can use HTTP only on the private Flycast
or `.internal` network; public endpoints require HTTPS. The checker needs no
Claude key, account key, database credentials or Phoenix secret.

GitHub secret `FIGURE_RUNNER_DEPLOY_TOKEN` contains a separate app-scoped deploy
token for `leitor-figures`, valid for one year. Keep the existing `FLY_API_TOKEN`
scoped to `leitor`. Pass token output directly to GitHub's encrypted secret input,
never through source files, logs or command-line arguments. Rotate before expiry.

The checker runs a trusted Docker daemon on its own Firecracker VM. Docker's
upstream DinD startup prepares nested cgroup controllers. A startup probe must
prove an inner networkless, read-only container can enforce memory/CPU limits
before the service becomes healthy. Generated modules execute only inside an
unprivileged inner container; they never execute in the service's Node process.
The inner container has no daemon socket, host credentials or network. The
public app calls its authenticated `/checks` protocol through Req with redirects
and automatic retries disabled. A busy checker refuses another execution rather
than exceeding its resource ceiling. Evidence expires from checker memory after
two minutes; PostgreSQL stores accepted account-owned artifacts and recovery.

Local service smoke test: build `figure_service/Dockerfile`, start the trusted
outer service in its own privileged Docker container (without mounting the host
socket), and submit an unchanged fixture through authenticated HTTP. This outer
privilege prepares its nested daemon only; generated inner containers retain all
resource and capability restrictions. Stop and remove the test service afterwards.
The real checker regression suite remains opt-in:
`LEITOR_RUN_SANDBOX_TESTS=1 mise exec -- mix test test/leitor/figure_runner_test.exs`.

The daemon uses `overlay2` for disposable writable layers. The original VFS
configuration passed local checks but exceeded the production request deadline
while preparing the full Chromium filesystem for a new container. VFS makes a
deep copy of parent layers; OverlayFS reuses immutable lower layers. See the
[Docker VFS documentation](https://docs.docker.com/engine/storage/drivers/vfs-driver/)
and [OverlayFS documentation](https://docs.docker.com/engine/storage/drivers/overlayfs-driver/).
The Fly kernel and backing filesystem must support overlay mounts; startup still
fails closed if the runtime probe cannot enforce its limits. This changes storage
preparation, not network isolation, user privileges, CPU/memory caps or deadlines.
Checker logs contain only job IDs, bounded outcome categories and elapsed time;
source, screenshots and credentials are omitted.

`figure_runtime` is a dedicated encrypted 5 GB Fly volume mounted at `/data`;
Docker uses `/data/docker` on that ext4 filesystem. Fly's application root is
itself an overlay filesystem and cannot be the writable upper layer of another
overlay mount. Provision the volume before publishing the corrective release:

```sh
fly volumes create figure_runtime --app leitor-figures --region gru --size 5
```

The archive's SHA-256 label identifies the cached runtime image across restarts.
Only obsolete untagged runtime images and stopped containers bearing the
`leitor.figure=true` label are eligible for startup cleanup. User artifacts stay
in PostgreSQL; request files remain temporary. Other images/containers are not
pruned. The volume is an operational cache, not a user-content backup.
