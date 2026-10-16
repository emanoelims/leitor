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
| AUTH-008 | Only pages, creation, the combined notes/word-jars notebook, per-page notebooks, and account screens remain in the product. Every product entry requires an authenticated scope. The legacy word-jars route redirects inside the authenticated scope; retired screens have no route. Only authentication screens remain in the public LiveView session. | `page_live_test.exs`, `notebook_live_test.exs`, `learning_workflows_test.exs`, and `controllers/workspace_routes_test.exs`. |
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
The `:current_user` session contains registration, login and confirmation screens.
There is no browser password login or password-update endpoint. Email settings require
recent authentication through an email link. Page annotations inherit ownership from
their parent text; browser-supplied quotes and owner IDs are never trusted.

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
