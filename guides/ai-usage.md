# AI usage and bounded waiting

Preferences show the current account's UTC-day credits, actual measured input
and output tokens, estimated API cost, active attempts and the last twenty
attempts. Reading costs one Leitor credit, writing two, and a figure four.
Credits are admission limits, not currency. Failed and canceled admitted attempts
keep their credit charge because provider work may already have occurred.

Application credentials remain restricted to Haiku. A personal encrypted key
allows the account's selected Claude model, subject to personal credit,
concurrency, token and time limits. No role bypasses these execution bounds.
Image and speech provider preferences do not enable external generation yet.

Provider responses contribute validated input, output, cache-read and cache-write
counters to their account-owned reservation. Reasoning is already included in
output. Missing, interrupted or incomplete responses are not recorded as free
calls. Old reservations have no invented measurements; their estimate is absent.
Costs may understate requests that failed or were canceled before usage arrived.
The activity screen explicitly marks incomplete data. Provider invoices remain
authoritative.

The estimate uses published standard-routing Claude rates checked on 2026-10-17:
[Claude pricing](https://platform.claude.com/docs/en/about-claude/pricing).
Rates live in `Leitor.AI.Usage`; unknown models remain unpriced. Estimates use
integer USD microdollars. Cache writes conservatively use the one-hour multiplier
(twice normal input); provider discounts, batch routing and negotiated terms are
not inferred. Update the dated rates and focused tests when adopting new prices.

## Waiting and recovery

When capacity or the account cooldown is busy, at most one figure request per
account may wait, with a global cap of fifty and a ten-minute expiry. Waiting
reserves no credits and contacts no provider. Queued cancellation and expiry
therefore cost no credits. A serving Phoenix instance checks the queue every
two seconds. Database row locks prevent duplicate dispatch across instances;
normal allowance, credential, cooldown and capacity checks run before admission.
Exhausted quota or an unavailable credential produces an actionable terminal
error instead of an automatic paid retry.

Once admitted, a worker owns the request independently of the browser. Recovery
reattaches without another charge; stopping cancels it. An interrupted running
request is never automatically resubmitted after a server restart. A subsequent
explicit retry uses normal authorization and may continue its private checkpoint.
Waiting requests can survive a restart because they have not contacted providers.

The remote checker may be retried only after an explicit `429` busy rejection,
within the original request deadline. A network failure, ambiguous admission or
accepted job is never resubmitted automatically.

## Operational data

Completion emits `[:leitor, :ai, :attempt, :stop]` with duration/count and bounded
operation, mode, model and outcome metadata. `ai_attempt_finished` logs contain
only operation, credential mode, outcome and duration. They omit account IDs,
prompts, keys, generated source and provider response bodies. Account activity
queries are ownership scoped. Measurements are operational estimates, not a
financial ledger or a replacement for provider billing.
