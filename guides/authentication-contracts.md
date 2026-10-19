# Authentication contracts

This register connects the current authentication behavior to its test evidence.
IDs are stable: extend a contract when its behavior grows and document migrations
when changing it. A passing test demonstrates its stated cases, not every possible
input, concurrent schedule, or deployment configuration.

| ID | Contract | Existing test evidence |
| --- | --- | --- |
| AUTH-001 | Registration requires a valid, unique email and creates an unconfirmed account without a password. The login form sends a generic response and only emails registered accounts; first-time readers use registration. | `test/leitor/accounts_test.exs`: `register_user/1`, including case-insensitive uniqueness. |
| AUTH-002 | Browser login accepts only a valid email-link token. Password submissions are rejected even when legacy credentials are valid; password-update routes and controls are absent. Existing password hashes and domain APIs are retained without exposing them to the browser. Remember-me remains available when consuming an email link. | `controllers/user_session_controller_test.exs`: email-only authentication; `live/user_live/login_test.exs` and `settings_test.exs`; existing domain password tests. |
| AUTH-003 | Session lookups reject unknown and expired tokens; logout removes the session token. | `test/leitor/accounts_test.exs`: session lookup and deletion; `test/leitor_web/user_auth_test.exs`: `logout_user/1`. |
| AUTH-004 | A confirmed user's magic link can be consumed once. Confirmation of an unconfirmed account revokes existing tokens. An unconfirmed account with a password cannot log in through a magic link. | `test/leitor/accounts_test.exs`: `login_user_by_magic_link/1`; session controller magic-link tests. |
| AUTH-005 | Email changes require a valid, unexpired token for the current email context. Rejected changes preserve the stored email and tokens. | `test/leitor/accounts_test.exs`: `update_user_email/2`; settings confirmation tests. |
| AUTH-006 | Protected routes require authentication. Email settings require authentication within the last 10 minutes. | `test/leitor_web/user_auth_test.exs`: `require_authenticated_user/2`, `on_mount :require_authenticated`, and `on_mount :require_sudo_mode`; `test/leitor_web/live/user_live/settings_test.exs`: `Settings page`. |
| AUTH-007 | Caller scopes retain the supplied user; an absent user produces no scope. | `test/leitor/accounts/scope_test.exs`: executable `Scope.for_user/1` examples. |
| AUTH-008 | Only pages, creation, the combined notes/word-jars notebook, per-page notebooks, and account screens remain in the product. Workspace entries require an authenticated scope; `/s/:token` authorizes optional-account visitors through explicit page permissions. The legacy word-jars route redirects inside the authenticated scope; retired screens have no route. Authentication and shared-reader screens use the public LiveView session. | `page_live_test.exs`, `notebook_live_test.exs`, `learning_workflows_test.exs`, and `controllers/workspace_routes_test.exs`. |
| AUTH-009 | Texts, page annotations, vocabulary, attempts, and hosted room management are filtered by scope; caller-supplied ownership is never cast. | `library_test.exs`, `pages_test.exs`, `notebook_live_test.exs`, `learning_test.exs`, `study_test.exs`: ownership cases. |
| AUTH-010 | The retained Study context authorizes invitation-based collaboration, host-only advancement and closure, and bounded messages. Participant metadata omits email. Room screens and routes have been retired; stored records are preserved. | Domain `test/leitor/study_collaboration_test.exs`: synchronization, rejection, chat, and closure. |

| AUTH-011 | Language and AI preferences at `/settings` use the existing authenticated session without requiring sudo mode. Updates cast only the caller’s embedded preferences, reject unsupported choices, preserve email and authentication tokens, and cannot target another account. Interface locale comes from the authenticated account, overriding browser parameters. | `test/leitor/preferences_test.exs` and `test/leitor_web/live/preferences_live_test.exs`. |

## Boundaries and limits

`Leitor.Accounts` owns account operations. `Leitor.Accounts.User` owns changeset
validation. `Leitor.Accounts.UserToken` owns token construction and expiry queries.
`LeitorWeb.UserAuth` owns browser sessions, route authentication, and LiveView hooks.
The context's default sudo window is 20 minutes; the settings hook explicitly
uses the stricter 10-minute window.

`Library`, `Learning`, and `Study` enforce resource ownership independently of
route authentication. A room invitation is a capability for collaboration, not
permission to mutate the host's resources. Protected LiveViews share the existing
`:require_authenticated_user` session and the browser authentication plug.
The `:current_user` session contains registration, login, confirmation and shared-reader screens.
There is no browser password login or password-update endpoint. Email settings require
recent authentication through an email link. Page annotations belong to their reader through an explicit `user_id`; browser-supplied quotes and owner IDs are never trusted.

Email delivery is tested through Swoosh's test adapter. These tests do not prove
production mail delivery. Production uses Swoosh's Resend adapter with a required
`RESEND_API_KEY` and verified sender address in `MAIL_FROM`; account emails use
the configured sender with the Leitor display name. The notifier regression test
checks the configured sender, recipient, and login URL. Credentials belong in Fly
secrets, never in source control. The public `/health` API endpoint checks database
readiness without creating a session or granting access to product screens.
SQL sandbox tests isolate database changes; they do not
prove every concurrent token-consumption schedule. No property or fuzz suite is
claimed by this register.

## Maintaining evidence

For behavior changes, run the nearest tests, add a focused regression case, update
the affected contract, and run `mise run precommit`. Test public behavior and useful
failure outcomes. Do not expose private helpers solely to test implementation
details. Keep test processes supervised and use monitors or explicit messages
for synchronization.

Use `mise exec -- mix test --cover --warnings-as-errors` to produce the built-in
line coverage report in `cover/`. Coverage measures executed lines, not the
completeness of these contracts. Do not exclude domain modules to improve a score.

Property tests are appropriate when a future parser, normalization rule, or domain
invariant benefits from generated inputs. Give them a clear invariant and an
independent expected result, preserve reduced failures as regression cases, and
include the suite in CI before claiming it as evidence. A separate fuzz or
benchmark framework is unnecessary until a concrete workload requires it.

## Account AI authorization

`/settings` remains inside the existing authenticated browser pipeline and
`:require_authenticated_user` LiveView session. No additional public route was
introduced. Reading preferences does not require recent authentication; saving
or removing provider keys requires the existing 20-minute sudo window.

`Leitor.AI` assigns credential ownership from the caller scope, encrypts input,
and omits plaintext/ciphertext from returned metadata. Deletion queries include
both account and credential IDs. Request-local credentials never modify global
provider configuration. Shared calls pin Haiku on the server even when a caller
saves a premium preference or forges browser model parameters. Personal keys
unlock supported models only for their owner; decryption failures never fall
back to the application's key. Quotas and concurrency are reserved transactionally
under database row locks before the provider is contacted. Finishing a lease is
scoped and idempotent, without refunding attempted credits.

Evidence: `test/leitor/ai_test.exs`, `test/leitor_web/live/preferences_live_test.exs`
and `test/leitor_web/live/page_live_test.exs` cover ownership, encryption, tampering,
key redaction, recent authentication, request model pinning, budget boundaries,
capacity, cancellation and unavailable credentials. These tests do not verify
provider credentials or every multi-machine concurrent schedule.

## Private executable figures

`GET /figures/:id` is a controller route in the authenticated
`[:artifact, :require_authenticated_user]` scope. The artifact pipeline accepts
JSON and shares session, CSRF, secure headers, locale and scope loading through
`:browser_session`. It is not a LiveView route.
Only a ready artifact with the caller's `user_id` can be fetched; drafts and
foreign IDs return 404. Private source and execution evidence are not exposed
by this endpoint. The browser receives only the accepted bundle, style and
integrity digest, with private no-store caching. Programs run in opaque-origin
iframes, never the application's JavaScript realm. The current artifact
reference does not grant another account access when pasted into its page.

Editor retries keep private checkpoint IDs in durable account-owned generation
records, never in client request parameters. Workers survive browser disconnects;
recovery reads the caller's latest attempt and does not reserve credits again for
running or completed work. Explicit figure adjustments accept only an owned ready
base revision before reserving credits. Failed adjustments cannot replace the
original executable figure. Only unchanged requests resume their saved source; changed prompt,
format, title or context starts a new program. `Artifacts.get_revision/2` still
checks the caller's scope. Each continuation reserves normal account credits,
and repaired code must pass fresh isolated execution and independent review.
Versioned coding checkpoints can reference the revision that established their
passing interaction and mechanical contracts. Resolving that reference also
requires the caller's account scope, valid source and successful execution
evidence. Foreign, missing, malformed and failed references are rejected before
calling the model. A restored contract does not grant execution or publication.
The existing authenticated `/pages/new` and `/pages/:id` LiveViews retain their
router scope and `:require_authenticated_user` session; no new route is added.

Evidence: `figure_controller_test.exs` covers authentication, ownership and draft
denial; `figure_program_test.exs` covers rejected reviews, foreign continuation
denial, persisted contract recovery and token bounds; `page_live_test.exs` covers request-bound continuation,
changed context, late checkpoint notifications, reconnecting to running and
completed attempts, and rejection messages; `generations_test.exs` covers scoped
recovery, cancellation, expiration and unauthorized base revisions;
`figure_runner_test.exs` exercises the real isolated compiler/browser explicitly
when `LEITOR_RUN_SANDBOX_TESTS=1`. Source-analysis tests are supplementary and do
not establish that arbitrary JavaScript can be safely executed on a host.

## Page sharing and reader privacy

`/pages`, `/pages/:id`, notebooks and account settings remain in the existing
`[:browser, :require_authenticated_user]` pipeline and authenticated LiveView session.
`/s/:token` is in the existing `:current_user` LiveView session with the `:browser`
pipeline: account authentication is optional, page authorization is mandatory.
The shared figure endpoint uses `:artifact` and independently checks the current
link, source-page membership, artifact owner and ready status on every request.
No owner identity is installed into a visitor session. Only the accepted bundle,
styles and integrity digest are returned; author source and review evidence stay private.
Shared responses disable caching, indexing and referrer propagation.

A share starts restricted. Only the page owner can change access, rotate the
random link, or manage email invitations. Link roles are `disabled`, `view` and
`comment`; editing is not granted in this first delivery. An explicit email grant
requires the matching confirmed account. Removing a grant does not remove broader
access supplied by a general link. Rotating a link invalidates older URLs, including
URLs previously sent to invited people; explicit grants remain on the new URL.
Revocation broadcasts contain only invalidations, and shared readers reauthorize.
Comment writes lock the sharing row and check access inside the transaction.

Visitors get a signed, HttpOnly browser identity, separate from account sessions.
A display name is unverified and grants no permission. Comment attribution and
source quotations are assigned server-side; submitted owner IDs and quotes are
ignored. Replies may reference only a comment on the same shared page. Only the
author or page owner can remove comment content; other people's replies are retained.
Comments are bounded to 4000 characters, six per actor per minute and 1000 per page,
with 50-comment pages. General links may be forwarded; use restricted invitations
when access must depend on a verified email.

Private page marks now have an explicit `user_id`, backfilled from their existing
page owners in the migration. A reader's notes and AI answers belong to that
reader, independently of the source owner, and remain in that reader's notebook.
Shared comments use a separate table and never include personal mark contents.
Guest drafts stay only in session storage in the current browser tab and are
revalidated against the current text before restoration. They are not uploaded as
shared comments or silently associated with an email address. After signing in, a reader
can explicitly import these drafts into their private notebook. The bounded import
is transactional and idempotent per reader, page and draft UUID.

AI and word jars require an authenticated account. Shared reading uses the current
reader's AI authorization, quotas, language preferences and credentials. It never
uses the page owner's private provider configuration. Access is rechecked before
saving the result. Original source changes invalidate in-flight selections and
cancel obsolete shared-reader AI work. Existing executable sandbox restrictions
also apply to shared figures.

Evidence: `sharing_test.exs`, `shared_page_live_test.exs`,
`shared_figure_controller_test.exs`, and `assets/browser-tests/sharing.spec.mjs`.
