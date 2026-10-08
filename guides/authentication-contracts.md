# Authentication contracts

This register connects the current authentication behavior to its test evidence.
IDs are stable: extend a contract when its behavior grows and document migrations
when changing it. A passing test demonstrates its stated cases, not every possible
input, concurrent schedule, or deployment configuration.

| ID | Contract | Existing test evidence |
| --- | --- | --- |
| AUTH-001 | Registration requires a valid, unique email and creates an unconfirmed account without a password. | `test/leitor/accounts_test.exs`: `register_user/1`, including case-insensitive uniqueness. |
| AUTH-002 | Password changes validate length and confirmation, hash the accepted password, clear plaintext data, and revoke the user's tokens. | `test/leitor/accounts_test.exs`: `change_user_password/3`, `update_user_password/2`, and password lookup. |
| AUTH-003 | Session lookups reject unknown and expired tokens; logout removes the session token. | `test/leitor/accounts_test.exs`: session lookup and deletion; `test/leitor_web/user_auth_test.exs`: `logout_user/1`. |
| AUTH-004 | A confirmed user's magic link can be consumed once. Confirmation of an unconfirmed account revokes existing tokens. An unconfirmed account with a password cannot log in through a magic link. | `test/leitor/accounts_test.exs`: `login_user_by_magic_link/1`; session controller magic-link tests. |
| AUTH-005 | Email changes require a valid, unexpired token for the current email context. Rejected changes preserve the stored email and tokens. | `test/leitor/accounts_test.exs`: `update_user_email/2`; settings confirmation tests. |
| AUTH-006 | Protected routes require authentication. Settings require authentication within the last 10 minutes. | `test/leitor_web/user_auth_test.exs`: `require_authenticated_user/2`, `on_mount :require_authenticated`, and `on_mount :require_sudo_mode`; `test/leitor_web/live/user_live/settings_test.exs`: `Settings page`. |
| AUTH-007 | Caller scopes retain the supplied user; an absent user produces no scope. | `test/leitor/accounts/scope_test.exs`: executable `Scope.for_user/1` examples. |

## Boundaries and limits

`Leitor.Accounts` owns account operations. `Leitor.Accounts.User` owns changeset
validation. `Leitor.Accounts.UserToken` owns token construction and expiry queries.
`LeitorWeb.UserAuth` owns browser sessions, route authentication, and LiveView hooks.
The context's default sudo window is 20 minutes; the settings hook explicitly
uses the stricter 10-minute window.

There are no reader resource contexts yet. Resource ownership and cross-user
authorization must receive their own contracts and tests when those features are
introduced; authentication alone does not establish resource authorization.

Email delivery is tested through Swoosh's test adapter. These tests do not prove
production mail delivery. SQL sandbox tests isolate database changes; they do not
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
