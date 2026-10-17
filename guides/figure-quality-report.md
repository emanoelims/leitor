# Original-generation quality campaign

On 2026-10-17, six frozen briefs in `priv/figure_evaluation.json` were generated
through the ordinary development preview path using an account-owned Opus 5.5
credential. Every initial case started with empty modules. No generated geometry,
simulation or checks were edited by hand, and quotas were not reset.

The campaign used six four-credit attempts (24 credits), each with the normal
65,536-output-token budget and twenty-minute deadline. Internal author/review
repairs shared that attempt's budget. A separately recorded four-credit Cardan
confirmation brought the total to 28 credits; it does not replace the original
case in the results. The engine evolved between cases, so these are development
acceptance examples, not a controlled benchmark or a predicted success rate.

| Brief | Seconds | Model checks | UI experiments | Automatic result |
| --- | ---: | ---: | ---: | --- |
| Universal joint | 636.35 | 19 | 6 | Accepted; later human prose finding |
| Cam and follower | 333.61 | 18 | 5 | Accepted; later host dark-text finding |
| Centrifugal governor | 367.68 | 18 | 6 | Accepted |
| Ratchet and pawl | 634.98 | 18 | 5 | Accepted |
| Optical refraction | 247.78 | 17 | 5 | Accepted |
| Lunar phases | 253.38 | 14 | 6 | Accepted |

All six demonstrated time-dependent drawing motion, stable reduced-motion
interaction, default mobile framing without clipping, and no external network
requests or runtime errors. Human checks additionally exercised playback,
pause, parameter changes, reverse blocking, total internal reflection, lunar
illumination and hemisphere orientation. Six unchanged accepted programs are
retained in `test/fixtures/figures/` and exercised by the real isolated suite.

## Findings retained in the result

The first Cardan model used `tan(theta_out) = cos(beta) * tan(theta_in)`, but its
explanation inverted the relation. The initial reviewer missed the contradiction.
Review now requires explicit equation/readout consistency and numerical evidence.
In the separate 61.5-second confirmation, review rejected the explanation using
the zero-angle gain (0.906 versus 1.103). The author corrected the prose and fresh
independent review accepted it. Model, geometry, drawing, checks, experiments and
CSS were byte-for-byte unchanged. The corrected accepted source is the Cardan
regression fixture; the original finding remains above.

The cam inherited black browser text on a dark background. A shared trusted
iframe/checker environment now supplies matching foreground and color-scheme
defaults before generated styles. The existing artifact became legible without
editing its source. A dedicated isolated regression covers both themes.

The governor's dark mechanical solids could still benefit from stronger contrast.
Its connected mechanism, bounds, controls and animation worked. Visual quality
is not uniformly perfect across unseen requests; model-authored checks and AI
review are bounded evidence, not a proof of scientific accuracy or aesthetic
quality. New domains still need representative human checks.

## Reproduction

`mix leitor.figure.evaluate --list` and `--case SLUG` inspect frozen briefs without
provider calls. Adding `--generate --user-id UUID` explicitly starts one ordinary
paid development attempt. It never loops through paid retries. Keep failures in
any new campaign denominator and record its independent credit ceiling.

Run unchanged retained programs without AI charges using:

```sh
LEITOR_RUN_SANDBOX_TESTS=1 mise exec -- mix test test/leitor/figure_runner_test.exs
```

The full isolated suite includes 23 cases, including older execution/security
regressions, these six programs and shared theme inheritance. PostgreSQL retains
the account-owned source and bounded review evidence. Local temporary captures
are not uploaded to production or committed as user data.
