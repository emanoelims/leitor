# Interactive figures

## Isolated program author

With `:figure_runner` enabled, authenticated page generation uses an authoring
loop rather than a fixed scene schema. Claude writes `model.mjs`, `geometry.mjs`,
`figure.mjs`, `checks.mjs`, CSS and observable browser experiments. Modules can construct
original geometry, articulation and state transitions using the bundled Anatomy
kit. They are not limited to the declarative engine's six primitive types.

For personal-model budgets, the native coding loop starts with empty program
files: the model reads kit documentation, writes the mechanism and its sampled
mechanical checks, geometry,
interface, CSS and experiment metadata, then renders and corrects its own work.
It does not receive a demo's geometry. Incomplete modules are checkpointed as
private drafts and can be resumed. Existing revision contracts, and new
experiments after their first passing render, cannot be weakened by subsequent
edits. Providers without coding tools retain the bounded structured or staged
author. The final source and experiments are validated with Ecto before
submission to a disposable container. A trusted checker parses imports and
capabilities, bundles with esbuild (without executing generated modules in Node),
and runs the result in Chromium. It checks controls, runtime errors, external
requests and mobile overflow, capturing initial, interacted, dark and mobile
screenshots. Claude receives that evidence for a separate visual review and can
refine the modules. The same coding-tool loop handles refinements: read fixed program
files and kit documentation, patch or write a bounded file, render in isolation,
inspect the resulting captures, and finish only after a fresh successful render.
There is no shell, arbitrary filesystem access or automatic tool execution. The
existing mechanical experiment contracts are preserved during refinement. Each
edit checkpoints a private draft, and a separate reviewer still decides whether
the result can be published. A successful compile alone does not publish a figure.
Authored program figures must also demonstrate time-dependent drawing motion.
After testing controls, the isolated runner probes their animation in a fresh
browser without reduced motion. If the experiments have not started playback,
it tries a uniquely named accessible Play/Reproduzir control. A changing button
label or a direct scrub does not satisfy this check: the SVG must change between
two observations separated by elapsed time. Failure withholds the executable
bundle and returns a repair diagnostic before visual review. Model-only checks
remain independent of drawing and animation. The existing data-only scene format
remains available for static compositions.

Visual review is a heuristic; mechanism-specific tests and human assessment
remain necessary. Generated experiments are evidence, not an independent proof
of physical correctness. The checker captures a detail frame immediately before
the final capture action (or final experiment action when none is supplied), so visual review can distinguish
pre-action contact from the final pose. The report image order is preserved;
missing or unsupported captures invalidate the response. Visual review receives
the rendered captures, mechanism model, geometry, authored checks, caption,
explanatory prose and test report. Source helps resolve actual joint coordinates
and cut planes; implementation style is not a substitute for visible correctness.
Minor aesthetic refinements are reported without blocking an otherwise polished,
correct figure. Intentional cutaway occlusion and required mechanical separation
are evaluated in context.

Optional `capture_steps` (up to eight ordinary UI actions) arrange screenshots
after all experiment assertions pass. They are separate from the immutable
experiment contracts: revising a visual pose must not weaken a mechanical test.
Invalid capture actions fail the check and prevent executable publication.
`tested.png` preserves the last tested pose before these actions, so inspection
evidence is retained alongside a clean assembled pose. Bounded DOM toggle and
output snapshots distinguish a pressed toggle from a focus/hover outline.

Automatic quality review can disagree with an operator's assessment. A trusted
development operator can create an explicitly curated private study with
`mix leitor.figure.curate --user-id UUID --source tmp/source.json --review tmp/review.json --previous UUID`.
The review file must record a `preview` decision, reviewer, rationale and
limitations; its maximum size is 6,000 bytes. An optional `--page UUID` updates
an owned page with a new immutable artifact. Previous automated criticism is
retained in the audit report. A fresh isolated check must still pass, the command
is unavailable outside development, and automatic generation keeps its normal
review gate. Curated previews must not be described as automatically accepted
or as proof of production readiness.

For a human repair pass, save a complete source JSON under ignored `tmp/` and run:

```sh
mise exec -- mix leitor.figure.check --source tmp/figure.json --output tmp/figure-check
mise exec -- mix leitor.ai.preview --user-id UUID --brief tmp/brief.txt --title "Visual study" --format visual_explainer --source tmp/figure.json
```

The check task calls no AI and publishes nothing. The preview task stages an
owned draft and uses the normal account authorization, isolated checks and
independent review. `--revision UUID` can instead resume an owned draft; it is
mutually exclusive with `--source`. Source import never bypasses the review gate.

In an open editor, rejected or interrupted program generation can retain a
private checkpoint. The composer distinguishes quality rejection, time/token
exhaustion and an unavailable checker from provider failures. When a checkpoint
exists, **Continue refining** resubmits the unchanged request against its saved
source rather than starting again. Changing the prompt, format, title or draft
context starts a new program. Account-owned `page_generations` records persist
instructions, a bounded editor snapshot, the last private revision, progress and
accepted results. Independently supervised workers own provider calls; closing a
browser or losing the LiveView connection does not cancel them. **Recover
generation** reattaches to a running attempt or inserts its completed result
without another provider request or credit reservation. Explicit cancellation
still stops work. A server restart does not automatically repeat paid requests:
expired attempts release their leases and offer an explicit checkpoint retry.
The most recent undismissed attempt is recoverable per existing page, or per
account's new-page editor. Saving the page or dismissing its notice clears that
association; immutable private revisions remain stored.
An already rejected immutable revision goes directly to repair with its stored
critique, avoiding an identical paid review before any edits. The repaired result
still requires a fresh isolated check and a new independent approval.

Checkpoint IDs stay server-side. The editor's **Adjust with AI** action can
instead submit the ID of an already accepted figure. The server validates its
ownership and ready status before reserving credits. Its next job edits that
source before requesting review; passing tests remain frozen. Only the figure
block is replaced after acceptance, leaving surrounding prose intact. If that
block has changed, insertion stops and the saved result remains recoverable.

Only the owning account can load a revision;
every continuation reserves normal AI credits and must pass isolated execution
and independent visual review again. Rejected code remains non-executable and
is never inserted into the page. Late checkpoint notifications from canceled or
completed requests are ignored.

Build the development runner from the repository root:

```sh
docker build -f figure_runner/Dockerfile -t leitor-figure-runner:1 .
mise exec -- mix ecto.migrate
mise run dev
```

The daemon must be running, and `tmp/figure-runs/` must be visible to its VM.
The runner has no host fallback. The container receives only the proposal in a
read-only input directory and a fresh output directory. It has no network,
credentials, repository, database or Docker socket; its root filesystem is
read-only, capabilities are dropped and resources are capped at two CPUs,
2 GiB memory and 256 processes. A container-side 75-second timeout survives
caller cancellation; canceled work may remain until that timeout. Host output
and wall-clock bounds apply as well. Source analysis is an additional diagnostic,
not a security substitute for isolation. Production uses the separate private
`leitor-figures` Fly Machine configured in `figure_service/fly.toml`. Never mount
a Docker socket into the public Phoenix application. See the deployment guide
for the authenticated private transport and release ordering.

Account-owned immutable revisions live in `figure_artifacts`: source, execution
and visual evidence, model, preview, and (only when accepted) a compiled bundle.
Rejected and interrupted proposals are drafts. The initial storage backend is
PostgreSQL with bounded payloads. Durable attempts recover browser disconnections;
external object storage, automatic recovery across worker crashes and an artifact
export package remain subsequent infrastructure work. Exporting a
page's Markdown currently exports its reference, not the program files.

An `anatomy-program@1` fence contains only title, caption and artifact UUID.
`GET /figures/:id` is inside the `[:artifact, :require_authenticated_user]` controller scope, sharing the
`:browser_session` plugs with the HTML browser pipeline and checks the owning scope;
it is outside `live_session` because it is a JSON controller response. Foreign,
missing and draft revisions return 404. Responses are private and non-cacheable.
The trusted bundled player verifies the bundle digest and constructs an opaque
`sandbox="allow-scripts"` iframe. Only the exact hashed script can run; network,
frames, workers, forms, plugins and base URLs are blocked by CSP. No generated
program is evaluated in the parent page. Size messages are checked against the
actual frame window. Theme, visibility and reduced-motion information form the
only lifecycle protocol. Each generation starts a new simulation when reopened.

The total reserved output budget covers authoring and review: shared credentials
retain Haiku and 6,000 tokens, with one attempt; personal credentials permit up
to 65,536 tokens across up to four attempts and their reviews. Opus 5.5 always reasons;
the native coding author uses `output_config.effort = medium` to reason about
assembly topology and the axial stack before drawing. Other bounded provider
calls retain their explicit low effort. If a coding response reaches the provider's
output limit, the next turns use low effort until a complete file edit is saved;
then normal medium effort resumes. Private stage handoffs preserve this recovery
state, actual token usage and frozen contracts, but never reuse execution evidence
after a new stage or edit. Recovery does not raise the model's total token or time
allowance or skip the independent review. These settings use the native effort
control rather than a legacy thinking budget or a request to disable thinking.
Source and review allocations include
reasoning tokens. Personal illustrated
generation has a 20-minute overall authorization, with provider-call and
container deadlines inside it. Reading and ordinary writing retain 90 seconds.
Credit charges and concurrent account/global leases still apply once per bounded
generation. Partial source is never displayed as finished executable content.

Verify the real container explicitly (the normal suite does not require Docker):

```sh
LEITOR_RUN_SANDBOX_TESTS=1 mise exec -- mix test test/leitor/figure_runner_test.exs
docker run --rm --network none --read-only --entrypoint node leitor-figure-runner:1 --test /runner/policy.test.mjs
```

## Authored compositions

Without the development program runner, AI generations use `anatomy-scene@1`. The model specifies every solid, its
position, orientation, dimensions, repetition, accent and declared motion. There
is no predefined apparatus, conveyor, base or station sequence. Available solids
are boxes, arbitrary-axis cylinders, hollow rings, spheres, gears and lathed
profiles. The bundled Anatomy camera and lathe helpers calculate the drawing.

The engine accepts 8–100 part definitions, expanding to at most 400 solids.
Each part can rotate about its own axis and move along a declared assembly-opening
vector. Controls open the assembly, pause motion, change speed and view angle,
and inspect named parts. Only those declared movements run: custom physics,
mechanical linkages, optical simulation and arbitrary generated programs are not
implemented. This is free composition within a geometric vocabulary, not the
complete Anatomy coding-agent workflow. Visual review remains necessary.

A structured model response is validated with Ecto before publication. Personal
requests use up to 16,000 output tokens, bounded by the lower authorized budget;
shared accounts keep their existing budget and Haiku restriction. Blueprints
preserve geometry in Markdown, with a 48,000-character generated-document limit.
Existing `anatomy-flow@1` blueprints remain compatible as the legacy workbench
engine described below. The slash menu explicitly labels its preset as Example
figure; it is not the source used for AI generation.

## Legacy workbench

Leitor's first figure engine is `anatomy-flow`, version `1`. It explains a
workflow using a physical workbench, built from the MIT-licensed Anatomy kit.
It supports discrete items moving through two to four stations. It is a
workflow metaphor, not a general physics or character illustration engine.

## Source and rendering

A `leitor-figure` Markdown fence contains a portable JSON blueprint: engine,
version, title, caption, accent, input interval, queue capacity and stations.
Each station chooses a bundled press, scanner or rotating wheel assembly and
an illustrative processing duration. The code generating the geometry, the
simulation and the controls is application-owned and bundled with `app.js`.
Generated content never supplies JavaScript, CSS, module names or asset URLs.

Blueprints are persisted with the owning page's Markdown through the existing
authenticated Pages context. Editing, importing and exporting preserve the
source and version. A page reload reconstructs the drawing and starts a new
simulation. Runtime counters and control settings are intentionally ephemeral.
There is no external image API or object-storage requirement for this engine.

The rendered SVG is derived, rather than stored as thousands of coordinates in
the document. Multiple instances own independent model state and controls.
The engine shares projection and shading with Anatomy; Leitor supplies the
original workbench assemblies and simulation. Upstream provenance and license
are retained in `assets/vendor/anatomy/`.

## Generation and bounds

Only interactive figures are currently available for AI generation. Output uses the program author when enabled, otherwise the authored-composition engine above. Other
forms appear disabled as coming soon; existing prose and older illustration
fences still render. The provider returns structured explanation and blueprint
data. Ecto validates the final result before it reaches the editor. The
loading state stays visible until a complete figure is available; partial JSON
is never presented as a finished scene. Normal cancellation, ownership, account
credentials, shared Haiku restriction and credit/concurrency leases apply.
The original flow generator used 6,000 output tokens; new generations use the authored engine budget described above.
The data-only engines do not run generated programs or perform automated visual critique.

## Simulation and accessibility

The pure flow model owns queues, individual items, station processing time,
blocking, completed work and rejected arrivals. A paused station retains work;
the previous station cannot hand off until the next slot is free. At most eight
items can wait and four can be processing. Drawing, dial and counters consume
that same state. No decorative random counter increments stand in for work.

Controls add an item, send a burst, pause each station, change time scale,
advance one second, reset and toggle automatic arrivals. Space on the drawing
adds one item; Right Arrow advances a second. Offscreen/hidden scenes stop
requesting frames and never catch up on elapsed background time. Reduced motion
starts paused and retains manual stepping. Themes follow reading appearance.
Disposal removes animation frames, observers and event listeners.

## Adding an engine

Implement `Leitor.Figures.Engine` with a typed value, validation, provider schema
and instruction. Register a fixed `{engine, version}` pair in `Leitor.Figures`
and its matching browser mount in `assets/js/figures/index.js`. Keep immutable
engine versions compatible with stored documents. Development generation targets the isolated program author when enabled;
other deployments target the authored scene engine. The registry decodes all
stored engine versions. Never dynamically load a module
named by a blueprint. New drawing vocabulary should reuse the bundled kit.

The original example is available from `/` → Interactive figure in the editor.
Use `node --test assets/js/figures/flow.test.mjs` for deterministic simulation,
conservation and geometry checks, plus the Elixir figure tests and normal
`mix precommit`/coverage workflow. Browser checks cover actual controls, saving,
reading, appearance, responsive layout and reduced motion.

## Reviewed lock demonstration

`test/fixtures/figures/lock-program.json` is the reviewed source of an interactive
five-pin lock. Its geometry adapts the MIT Anatomy Community study by Nader;
the attribution is retained in the source, page prose and bundle notices.
Leitor provides the user-controlled simulation and integration. The demo tests
wrong, partial and correct keys, rotation retention, reset, real animation and
reduced motion. It is a regression fixture, not a preset used by the author.

## Original iris study

`test/fixtures/figures/iris-program.json` contains a camera diaphragm authored
from blank native-tool files, then revised by Codex for blade profiles, depth
ordering and presentation. It uses the MIT projection kit, not an Anatomy
figure's geometry. This is evidence of original program authoring, not proof of
consistent autonomous quality across arbitrary subjects. The source remains a
regression fixture and is never seeded into a new generation.

The study provides continuous aperture control, f-number presets, stop limits,
cycling/pause, reset, isometric/axial views, zoom and an explicit inspection mode.
The fixed retaining plate and command ring can be made transparent for inspection;
normal presentation is opaque. Ordered 3D face fragments resolve leaf occlusion.
The ideal optical readout uses the inscribed circle and a 50 mm, 1:1-pupil lens;
it is an educational mechanism, not a manufacturing or calibrated optical model.

`iris-invariants.mjs` is an independent test probe executed only in the isolated
browser. It checks six aperture positions, 2D and 3D rigidity, fixed pivots,
attached followers, slot alignment, housing clearance, a numerically sampled
opening and the quarter-flux relationship when doubling f-number. These checks
complement the six real-control experiments, animation/reduced-motion evidence,
theme and mobile captures; they do not prove absence of every part collision.

## Reusable opaque surface ordering

Leitor's own MIT helper lives in `assets/js/figures/kit/occlusion.mjs`, separate
from the unchanged vendored Anatomy kit. Isolated programs may import it as
`/leitor/occlusion.mjs`, and the coding tools expose its actual source. The iris
regression uses this shared implementation instead of carrying a private copy.

The helper partitions convex planar faces and line segments at caller-supplied
planes, retains material/part metadata and returns far-to-near fragments for an
orthographic camera. Whole-solid centroid sorting cannot represent cyclic
overlap. Correct partition planes resolve that overlap without making steel
transparent. Remaining unpartitioned cells use a centroid fallback; this is not
a general collision, constructive-solid or transparency solver. Input and
cumulative fragment limits fail explicitly rather than dropping geometry.

## Original slider-crank study

`test/fixtures/figures/crank-program.json` is an original Codex-authored bench
mechanism, constructed locally after the account's daily AI quota blocked a new
Opus request. No credit limit was reset, refunded or bypassed. It exercises the
same shared occlusion helper with a flywheel, rigid connecting rod and guided
slider, rather than iris geometry. It is another regression fixture, not a
generation preset or evidence of an automatically accepted Opus result.

The 24 mm crank and 80 mm rod use exact in-line loop closure, producing a 48 mm
stroke. Six browser experiments exercise end positions, non-sinusoidal travel,
continuous angle input, reversal, inspection, top view, zoom and reset. A separate
browser-only probe samples 721 positions to verify the fixed radius, rod length,
joint closure, guide axis, travel bounds and consistent readouts. Play/pause uses
bounded frame deltas; reduced-motion users get a deliberate 15-degree step instead.
The figure honors visibility, themes and disposal. These checks concern ideal
kinematics and rendering, not forces, tolerances or manufacturing feasibility.

The pure occlusion regression tests run with `mix precommit` and in CI. Real
Chromium/container tests remain opt-in with `LEITOR_RUN_SANDBOX_TESTS=1` after
building the pinned runner image.


## Reusable mechanical geometry

`assets/js/figures/kit/mechanics.mjs` is an original MIT module, available inside
the isolated runner as `/leitor/mechanics.mjs` and to author tools through
`read_file("mechanics.mjs")`. No complete apparatus is supplied to the model.
The coding instructions recommend these primitives for supported mechanisms.

- `spurGear` samples actual involute flanks for unshifted 20-degree external
  gears (20–160 teeth), returning dimensions and a concave CCW profile. Its root
  connection is a radial extension/circular land, not a cutter-generated fillet.
- `externalGearPair` derives compatible profiles, pitch center distance, speed
  ratio, contact ratio and shared-plane tooth phases from one specification.
- `sliderCrank` returns both joint centers, rod orientation and displacement from
  exact in-line closure, for either slider side.

The geometric conventions follow [KHK's standard spur-gear calculations](https://khkgears.net/new/gear_knowledge/gear_technical_reference/calculation_gear_dimensions.html)
and the [METU slider-crank course](https://ocw.metu.edu.tr/pluginfile.php/3961/mod_resource/content/11/ch7/7-2.htm).
The restricted tooth range avoids promising arbitrary undercut/profile-shift
handling. These are educational kinematics, not a stress, contact dynamics,
manufacturing or thermodynamics solver. Backlash reduces EACH gear's pitch tooth
thickness; it is not simulated lost motion. Concave profiles must use `mPrism`;
`G.prismOf`'s convex hull would erase the tooth gaps.

Independent numerical regressions check dimensions, pitch thickness, concavity,
scaling, opposing rotations, five gear ratios (including minimum/maximum tooth counts, sampling and backlash boundaries) over complete revolutions and
slider-crank joint closure at 721 angles on both branches. A deliberately wrong
gear phase must collide, verifying that the polygon probe detects overlap.
These bounded samples complement visual and browser tests; they do not certify
all parameter combinations or replace independent review of generated drawings.
The pure tests run in the existing precommit and CI kit checks.


`test/fixtures/figures/mechanics-program.json` is a Codex-authored verification
bench using these imports in the real isolated browser. Its two involute gears
(20:40, module 1.5) drive a rigid radius-8/rod-30 slider-crank. It tests locking,
opposed half-speed output, travel limits, two input revolutions, detail view and
reset, plus animation, reduced motion, themes and mobile layout. An independent
721-position probe checks physical closure and readout consistency. The fixture
is not sent as a preset to authors and is not an automatically approved AI result.

## Sectioned steam-mill regression

The steam-mill study is repaired from the original Opus draft with explicit
world-space geometry, rather than a generic whole-machine preset. Its source
and independent browser-only physical probe live in
`test/fixtures/figures/steam-program.json` and `steam-invariants.mjs`.

The cylinder has a real rear half-shell, annular rod gland and a solid ringed
piston. Its 26-unit piston rod terminates at a forked crosshead: separate bored
cheeks receive the forged connecting rod's small eye and a shared journal pin.
Piston, rod, crosshead and both connecting-rod eyes share one slider-crank pose. The physical probe checks 721 crank positions, piston containment, rod
length, journal closure, guide alignment and gear phases. The fibre route joins
tangent lines and arcs through the two actual nip midpoints. It checks 2,001
route positions against all three roller surfaces, plus positional/tangent
continuity, clearance of the curved transfer plate, downhill discharge above
the platform, and one-stalk completion. These tests supplement the six preserved
browser scenarios and visual review; they do not certify manufacturing or
thermodynamic performance.

The floor paints before machinery above it. Rods are split at gland planes,
and the fibre working plane paints in front of the retained rear roller sections
in the inspection view. Normal assembly remains opaque. Detail views document
their omitted parts and expose interactive crank positioning and pause. Engine
inspection removes the nearest upper guide cap to reveal the clevis; normal
assembly retains it. The mill cutaway shortens barrels to the actual working plane and removes the
front journal frame and forward shaft lengths. It retains bored, bolted rear
journal housings, bearing pedestals and an open supporting gantry on the
foundation; the complete view retains both structural frames.
The exposed section uses the full barrel radius, not the chamfered physical
end profile; the view separates the retained rear bearing housings from the fibre plane. It
shows the two numbered crushing gaps, transfer plate and steep separate bagasse
chute. The finite stalk has a marked leading tip; a dashed guide shows its
remaining route without pretending material has already reached the outlet.
Bolted flange housings distinguish the supported journals from rotating hubs.
Juice streams fall beside the front pedestals into the liquid tray. The separate
bagasse receiver lies outside that vessel, with no overlapping piles or walls.
The juice vessel rests on a continuous low plinth; the discharge saddles follow
the chute slope so support caps cannot pierce its surface. Genuine orthographic insets expose gear meshing and the full
fibre route. A resize observer reframes these details on narrow screens.

The representation follows the [German Museum of Technology's piston–crosshead–rod explanation](https://artsandculture.google.com/story/what-s-a-steam-engine-deutsches-technikmuseum/OQWx9RekSvVUJQ?hl=en)
the [three-roll feed/top/discharge arrangement documented in US5855168A](https://patents.google.com/patent/US5855168A/en),
and the [transfer plate between the two lower rolls documented in US4378253A](https://patents.google.com/patent/US4378253A/en).
It is an ideal educational model, not a calibrated historical-machine replica.

For manually repaired sources, `mix leitor.ai.preview --review-only --source
path --user-id UUID --brief path` performs fresh isolation and the same visual
review without authoring any new code. It requires an explicit source before
reserving normal account credits. A rejection remains private and non-executable;
acceptance follows the usual reviewed-artifact publication path. This mode does
not bypass quotas, the independent verdict, ownership or browser checks.


## Automatic mechanical regressions and bounded repairs

New native-tool figures are authored from empty modules, including `checks.mjs`.
Its synchronous `verify()` imports the actual pure model and returns 3–24 uniquely
named `{name, passed}` records. Checks should sample a full cycle, joint contact,
travel limits, dwell and actual state transitions. They execute inside the same
networkless browser before mounting the interface. Optional bounded `detail`
strings report actual values and failing angles. The native `verify_model` tool
can also execute these checks before geometry and UI exist, using the same
networkless container. It returns only model evidence: no executable bundle,
images or full-render verification, and it cannot satisfy `finish`. This lets
the author repair equations before constructing the illustration. A run records all returned
constraints together, including failures, so repairs do not need a separate
render just to uncover each subsequent defect. Failure prevents publication;
legacy figures without this module remain compatible. The checks are authored
regressions, not an independent mathematical proof. The independent reviewer
receives their source, the model, geometry, execution report and actual captures.
Constant success flags and tautological checks do not establish correctness.

The first successful render freezes the UI experiments and existing mechanical
check source. Additional checks can be appended as `verifyExtra1()`,
`verifyExtra2()`, etc. The runner executes all verifiers: an added failure blocks
publication, and the existing source prefix cannot be altered or removed.
Visual repairs must preserve those contracts. Previous review findings remain in
the correction context, including saved continuations, so fixing a collector
does not silently undo a joint fix. Review feedback triggers structural repair
guidance: centralize real XYZ dimensions and axial intervals in the model,
rebuild affected geometry where necessary, and verify 3D contact rather than
covering the defect with an inset, dashed lines or prose.
Personal illustration jobs can use up to four author/review attempts within the
existing 65,536-token reservation and 20-minute deadline. Each allocation reserves
tokens for subsequent reviews and minimum repair work; shared-account allowances
and credential boundaries remain unchanged. Exhaustion preserves a private draft.
If construction or repair exhausts only its coding-stage allocation between
edits, the agent can continue those exact private files in another remaining
stage. The handoff includes the frozen interaction assertions and mechanical
check prefix, including contracts established by a successful render within the
current stage. Those contracts remain immutable in the next stage; its cached
render is cleared and the edited source must execute again. A partial handoff
therefore cannot reset passing checks or publish a stale bundle.
Each partial handoff consumes one of the bounded authoring attempts.
Coding and render checkpoints also retain the last six visual findings. A later
owned-draft continuation reads that repair history before requesting another
review, including when a token limit interrupted the repair. Saved review history
is context for a correction, never approval or reusable execution evidence.
New coding checkpoints include versioned recovery metadata and a reference to
the immutable revision that established their passing contracts. On a later
owned-draft continuation, the agent resolves that reference through the same
account scope and requires a valid source with successful execution evidence.
It restores the frozen experiment list and mechanical-check prefix even if the
latest module is incomplete. The reference avoids duplicating large source or
assertion payloads inside the bounded report. Foreign, missing, malformed and
failed references stop before any provider call. Legacy checkpoints retain their
existing continuation behavior; malformed new recovery metadata cannot fall
back to that path.
An older in-memory baseline without a stored successful reference is never
relabeled as an unfrozen new checkpoint. It retains legacy metadata until a
successful persisted render establishes the versioned contract reference.

Checkpoints created before the first passing render explicitly have no frozen
reference: their still-unverified assertions remain editable. Recovery effort
and final spent usage are checkpointed on stage exhaustion, including a response
that hit its token limit without saving an edit. A later job can continue that
recovery without repeating initial planning or prematurely reviewing a complete
but unverified draft. Each new job still uses normal account authorization and
its own bounded token/time reservation. Restored contracts grant no cached
execution evidence: the final source must pass isolation and visual review again.
Actual spent tokens are deducted from the same reservation, and the next
allocation still reserves review capacity. No render evidence or executable
publication is granted by this partial handoff; the complete source must pass
the normal isolated run and independent review. Overall deadlines and exhausted
reservations still stop the job.
Native continuations keep using coding tools even when the remaining stage is
smaller than 6,000 tokens. The structured provider schema describes shape only;
unsupported provider length/item constraints are enforced by local changesets
and the runner instead, preserving all source and experiment bounds.

## Automatically authored Geneva mechanism

`test/fixtures/figures/geneva-program.json` is the unchanged source of an approved
six-slot external Geneva drive. Its model, drawing and simulation began as empty
modules; no generated geometry or simulation was manually edited. During engine
development, several bounded jobs and owned-draft continuations were needed to
expose and fix stage handoff and provider-schema errors. This is evidence for
the resulting author/test/repair loop, not a claim of single-attempt success.

The final automatic repair used `verify_model` before full renders, preserved the
original checks and appended stronger constraints. Seventeen sampled mechanical
checks cover two 60-degree indexing cycles, the 240-degree dwell, continuous
output, pin-slot clearance, axial engagement, disk-to-wheel clearance and forcing
the output in both phases. Six browser experiments cover scrubbing, locking,
single-turn advance, inspection and play/pause. The separate reviewer accepted
the actual light, engaged, cutaway, dark and mobile captures. The fixture runs
through the opt-in sandbox regression suite; future requests still require their
own model checks, isolated interaction tests and independent visual approval.

A successful native editor render is reused for independent review only when its
validated source exactly matches the returned source. A later edit invalidates
that evidence. Ordinary provider JSON cannot supply trusted cached execution.
This avoids a duplicate container run without bypassing isolation or visual review.
If the coding stage runs out of tokens immediately after a fresh successful
render, its verified source proceeds to independent review without another model
call just to say `finish`. Expired jobs or sources changed since the last render
remain blocked. The total reservation and publication gate still apply.
The runner's production deadlines are unchanged; opt-in ExUnit container tests
allow time for those deadlines plus cleanup rather than timing out prematurely.
After every interaction assertion passes with reduced motion, the separate
animation probe stops as soon as it observes an actual time-dependent drawing
change. Replaying the remaining controls under continuous animation provided no
additional assertion coverage and could exhaust the container deadline.

## Automatically authored screw jack

`test/fixtures/figures/jack-program.json` is the exact source of an independently
approved scissor screw jack, produced from initially empty modules. No generated
geometry, state transition or animation code was manually edited. Several bounded
editor jobs and owned-draft continuations were needed while improving the engine;
this is not a single-attempt success claim. A separate repair request used the
normal development preview task, account credentials, quota and review gates.

The first visual review rejected disconnected-looking cutaway joints. Automatic
repairs added connected sections and tighter framing. Browser verification then
found a separate defect that visual review had missed: the play button changed
its label, but the frame timestamp reset on every tick and the mechanism stood
still. The new mandatory motion gate reproduced that failure and withheld its
bundle. The author repaired scheduling and added sampled elapsed-time checks;
the unchanged repaired source passed isolation and independent visual review.

Twenty-four model checks cover fixed arm length, screw engagement and pitch,
sector contact, three-dimensional clearance, travel limits, variable lift per
turn, timed playback, stable pause, reversal and reset. Five original browser
experiments remain unchanged. Real reader checks additionally confirmed that
playback changes both turns and height, reversing lowers the jack, pausing holds
the position, and the cut and reset controls work. The sandbox regression checks
light, cutaway, dark and 390-pixel mobile views, observed motion and the absence
of external requests or runtime errors. The illustration models kinematics only;
it makes no load-capacity or force claims.

## Private production checker

The trusted `figure_service` process operates Docker inside a dedicated Fly
Firecracker Machine. Only Flycast private IPv6 ingress is allocated. Authenticated
POST `/checks` accepts fixed, bounded program files and returns a job UUID;
authenticated GET `/checks/:id` polls for bounded reports, PNG captures and the
accepted bundle. Provider keys, account credentials, database connections and the
Phoenix filesystem never enter this service. Redirects and automatic HTTP retries
are disabled. The generated program runs only in a fresh inner container with
the same networkless, read-only, unprivileged and resource-limited configuration
as local checks. The host's Docker socket is never mounted in that container.

A startup probe verifies that the nested runtime can enforce its resource limits
before health becomes ready. The checker admits one execution at a time and
rejects concurrent submissions with 429; completed in-memory responses expire
after two minutes. Individual checks retain the 75-second container and
100-second host deadlines. A failed or model-only report cannot provide an
executable bundle. Stable GitHub releases deploy this private service before
Phoenix. PostgreSQL retains final account-owned artifacts; the checker's job
files and containers are disposable.
