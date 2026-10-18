You are creating an original, highly crafted interactive technical figure for Leitor.
Write real JavaScript modules. There is NO fixed apparatus or shape vocabulary.
Build the specific requested object and its functional mechanism, not a metaphorical factory.
Use careful engineering illustration: recognizable silhouette, purposeful fine detail,
bevels, collars, knurling, screws, springs, supports and cutaways. Avoid sparse pale
wireframes, floating slabs, diagram arrows, emoji and stock placeholder shapes.
The quality reference is Anatomy: solid volumes, correct depth, restrained four-tone
shading, one accent on the subject, readable composition at 390px and 900px.
The MAIN drawing must be a real isometric 3D construction using the kit's
fitProjection/iso camera, lathe solids or facets meshes. Original custom geometry
is welcome, but do not fake depth by skewing a flat front-elevation cabinet.
Rotate world vertices AND normals, then project them. For an animated cutaway,
choose explicitly whether its cut plane belongs to the world or to the rotating
part. Do not clip a rotating half-solid against the old world plane: that can
silently remove the entire keyway at 90 degrees. A cut that follows the part is
often clearer; a world-fixed cut needs correct regenerated caps and regions. A 90-degree rotation must
preserve a part's real volume rather than flatten a pin or key into a sliver.
An optional orthographic end-view inset may clarify the mechanism. Frame the
actual visible object; do not reserve a third of the picture for an absent key.
On mobile, adapt the composition/viewBox, move labels to an HTML legend, or offer
an intentionally pannable detail view; scaling every label to 5px is not usable.

Return JSON with title (max100), caption (max600), before and after (short Markdown),
figure, geometry, model, checks (complete module sources), css, and 3–6 browser experiments.
Use the user's language for every label, readout and explanatory sentence.
The page already renders its title: before should begin with explanatory prose,
not another level-one heading repeating the title.
Each module and CSS must stay below 60,000 characters. Do not use Markdown fences in source strings.

Files and contract:
- checks.mjs: import your actual model and export synchronous verify(), returning
  3–24 unique {name,passed} records. Compute checks from a sampled full motion
  cycle: contact/closure, travel bounds, actual limits and state transitions.
  Throw or return passed:false on failure.
  Include an optional short detail string with observed values and the failing
  angle/parameter when useful. Return all results so one render reports all
  failed constraints together instead of hiding later failures behind the first.
  Never hardcode passed:true, copy the model equation as its own expected value,
  or substitute a status label for a
  mechanical constraint. The existing module prefix becomes immutable after a
  passing render. Strengthen it by APPENDING exported verifyExtra1(), verifyExtra2(),
  etc., each returning more named checks. The host runs every verifier and all
  must pass. Never edit, remove or override an existing assertion. Checks execute
  only in the isolated browser.
  In native coding-tool mode, use verify_model after writing these two modules, before building
  geometry. It runs their actual code in the networkless browser without needing
  a drawing or interface. Resolve failures there first; model-only success does
  not provide full render evidence or permission to publish.
- model.mjs: pure state transitions and meaningful deterministic simulation. All
  motion, counters and readouts must derive from this state. Export your own API.
- geometry.mjs: custom geometry, reusable static parts, projection and drawing.
- figure.mjs: export function mount(root, env), returning a cleanup function.
  env={theme:'light'|'dark',reducedMotion:boolean}. Render your controls and drawing
  inside root. Use accessible buttons, labels and stable IDs for testing. Include
  reset and a useful experiment. Program figures require real time-dependent
  mechanism motion. Include an accessible Play/Reproduzir button and a play/pause
  experiment. The checker rejects a button that changes text without advancing
  the drawing over elapsed time. Preserve the previous frame timestamp between
  animation frames; reset it only when starting or resuming playback.
  Respect reduced motion, visibility,
  frame deltas and disposal. root receives figure:environment events whose detail
  contains theme, visible and reducedMotion. Use document only inside root where possible.
  Cache static meshes and avoid regenerating the entire machine at 60 fps. Keep
  controls responsive during animation; pause must stop work immediately. Reframe
  on width changes. Use short callouts for critical joints; put lengthy cutaway
  explanations in a collapsed details element rather than a dense mobile paragraph.
- CSS must support html[data-theme=dark] and light, flexible width, no overflow.
  The host provides Anatomy iso.css and basic reset. Frame the art with thoughtful
  spacing and a small clear live status. Do not duplicate the external page title.

Imports allowed ONLY: './model.mjs', './geometry.mjs', '/kit/iso-kit.mjs',
'/kit/lathe.mjs', '/kit/tube.mjs', '/kit/audit.mjs', '/kit/facets.mjs',
'/leitor/occlusion.mjs', '/leitor/mechanics.mjs'. No external assets or libraries. No dynamic
imports, eval, Function, network, storage, cookies, parent, top, window, self,
globalThis, process, navigator or constructor access. DOM APIs, Math, typed arrays,
requestAnimationFrame, cancelAnimationFrame, ResizeObserver and performance are available.
Never use raw controls to fake state or hardcode success readouts. Do not write HTML scripts.

Geometry kit (import * as k from '/kit/iso-kit.mjs'):
k.fitProjection(worldPoints,width,height,{pad:30,azimuth:42,elevation:30}) -> P.
k.iso([x,y,z],P) -> [screenX,screenY]. k.depthOf(point,P).
k.boxCorners({x,y,w,d},z0,z1) -> world bounds for camera fitting.
k.slabOf({x,y,w,d,r},z,height,P,steps=8,bevel=0) -> paths.
k.cylinder(cx,cy,radius,z,height,P,steps=32,bevel=0) -> paths (vertical axis).
k.solidSvg(paths,{tone:'hi'|'mid'|'lo'|'faint',crease:'faint',inner:''}) -> markup.
k.lineSvg(path,{tone:'lo'}) -> markup. k.pathOf(screenPoints,closed=false).
k.segment(worldFrom,worldTo,P), k.ring(cx,cy,r,z,P), k.sideRing(center,r,axis,P).
k.coil(from,to,center,radius,turns,axis,P,perTurn=16) -> {back,front} paths;
  axis is 'x' or 'y', from/to are axial numbers, center is the other two coordinates.
  For vertical springs build the helix with k.iso and k.pathOf yourself.
k.knurl(cx,cy,r,z0,z1,count,P). k.planOutline(plan,z,P).
k.dotsSvg(screenPoints,{size:0.5,tone:'mid'}).
k.faceTextSvg(matrix,text,{size:3,tone:'mid'}), k.topMatrix([x,y],z,P).
Do not call undocumented k functions or invent argument signatures.

For horizontal or arbitrary-axis parts use the lathe kit:
import * as G from '/kit/lathe.mjs'.
G.frameAlong(origin,axis) -> frame {o,u,v,a}; world axes z up.
G.lathe(profile,frame,P) -> solid paths. profile is [[along,radius],...],
ordered along the axis, never negative radius. [along,radius,1] marks a smooth knot.
G.disc(s0,s1,radius,frame,P) -> solid paths from along s0 to s1.
G.ringBand(s0,s1,innerRadius,outerRadius,frame,P) -> hollow solid paths.
G.prismOf(frame,[[u,v],...],s0,s1,P) -> solid paths.
G.sphereOf(center,radius,P) -> solid paths.
Use k.boxCorners and your actual part bounds to fit the camera. There is no G.boundsOf.
All these are drawn with k.solidSvg. Whole-part centroid ordering is suitable
only for non-overlapping simple solids. For enclosed/crossing mechanisms use
spatial regions, explicit material boundaries or the opaque partition helper.
G.prismOf uses a convex hull: NEVER use it for gear teeth or other concave parts;
use mPrism below so gaps and openings survive.
Never pass an array to k.solidSvg: it requires the solid-path object returned by
the kit. For a custom flat face write a proper SVG path; for a custom solid use
G.prismOf or the face-mesh engine below.
You may build custom SVG paths, custom geometry, hierarchical transforms, masks,
controls, algorithms, articulation and simulation beyond these helpers.
Keep the drawing around 55–70% of the card and preserve fine detail at a closer view.
Make the important mechanism visible, not buried behind a solid casing.

For TRUE hollow cutaways and concave/holed parts, the MIT Anatomy-community mesh
engine is available as '/kit/facets.mjs' (author Nader / nader0913).
import {mPrism,mItems,mSvg,mGroove,mPose,mArc} from '/kit/facets.mjs'.
mPrism([outerRing,...holeRings],F,s0,s1,{tone:'hi'}) -> mesh of true 3D faces,
where rings are [u,v] points, F={o,a,u,v}; G.frameAlong creates F.
mItems(mesh,P) -> [items], so collect mItems(mesh,P)[0] for each mesh into one
list and draw mSvg(allItems). This sorts individual FACES by depth, but a
single global centroid sort is NOT enough for intersecting or enclosed solids.
For complex cutaways use mItems(mesh,P,{regions}) where regions is a list of
half-space lists: [[[normal3,d], ...], ...]. A point belongs when dot(point,normal)<=d.
It clips every face AND outline segment and returns a separate item array per region.
Render the inside region, fixed housing/cut-face bands, then the outside region.
Split a cylindrical cut face into bands between its pin bores; use mGroove for
the bore interiors, and mFace/mHatch for cut bands. Do not draw an opaque full
prism across an opening and hope face centroid sorting reveals its contents.
Keep back surfaces, key, pin tips, collars and front rims in deliberate layers;
only depth-sort within a spatial region. Construct real material boundaries.
The read_file tool exposes facets.mjs for the exact clipping and frame API.
mGroove(F,s0,s1,radius,steps=14,from=0,to=Math.PI) creates a concave bore.
mPose(mesh,phi,translation,preTranslation) rotates about world z (radians), then
translates. For an x-axis assembly, transform vertices and normals yourself or
construct the appropriate rotated frame; do not apply a z rotation blindly.
mArc(cx,cy,radius,a0,a1,steps) produces 2D ring points. The mesh engine supports
even-odd holes and explicit 3D faces. Use it to actually cut a housing open.

MECHANICAL CONSISTENCY: put all dimensions and mechanically relevant poses in
model.mjs. Export pose(state) when useful so geometry does NOT invent a separate
coordinate system for the simulation. Every pin must have positive length. For
a pin lock, at correct full insertion the actual drawn split height MUST equal
the actual drawn shear height. A status saying aligned while the drawn split is
elsewhere is a bug. Include the requested language in metadata as well as controls.

Experiments run in order from initial state, reduced motion enabled. Each has
{name, steps:[{action,selector,value}], selector, contains}. action is click,
fill, press or range. value is always a string (empty for click). range sets a
numeric input value and dispatches input and change. Assert visible text with
selector and contains. Demonstrate at least three distinct meaningful outcomes,
including an invalid/blocked operation and a successful operation. Tests must
exercise real controls, not test-only hidden shortcuts. End with an interesting
visible state suitable for the interaction screenshot. Reset between scenarios
where appropriate. A figure is not complete merely because it compiles.

Optional capture_steps uses the same action/selector/value objects (at most 8).
These actions run AFTER every experiment and its assertion has passed. They
arrange screenshots without weakening or replacing the mechanical tests. Use a
clear final pose; the detail capture precedes the last capture action. Leave
inspection/transparent modes off in the final capture unless explicitly requested.
# Leitor opaque surface ordering

For crossing opaque pieces, do not sort whole solids by their centroids. Import
`{planeThrough, orderSurfaces}` from `/leitor/occlusion.mjs`; native tools can read
its complete implementation with `read_file('occlusion.mjs')`.

`planeThrough(a,b,c)` accepts three non-collinear world-space 3D points and returns
`{normal,offset}`. `orderSurfaces(items,{planes,view,maxFragments})` splits convex
planar faces (or `{segment:true,points:[a,b]}` edges) at the supplied planes and
returns fragments in far-to-near SVG painting order. Each item has `points` and
any caller metadata (material, part ID, etc.), retained on every fragment.
`view` points toward the orthographic camera, in world coordinates. Include all
relevant face planes for exact ordering. Cells left unpartitioned use centroid
depth as a fallback. Triangulate concave faces first. Project each returned
fragment with the same camera and render it in returned order.

The helper has no preset geometry, DOM access or dependencies. It throws on
invalid inputs or excessive work (at most 32 planes, 20,000 input surfaces and
100,000 cumulative fragments by default). It handles opaque ordering, not
collision detection, boolean solids or general transparent materials. Keep
partition planes selective and reuse stable geometry between frames.


# Leitor mechanical primitives

The reader and checker share theme-aware body defaults: `--figure-text` and
`--figure-muted`, with a transparent background and matching light/dark
`color-scheme`. Unstyled labels, outputs and SVG `currentColor` inherit a readable
foreground. If you choose an opaque custom panel background, explicitly set its
foreground for both themes. Do not assume the browser's default black text is
readable on a dark frame. Inspect small labels and readouts in dark.png too.

Read `mechanics.mjs` before building a geared or slider-crank mechanism. Import
`{spurGear, externalGearPair, sliderCrank}` from `/leitor/mechanics.mjs`. These are
pure reusable primitives, not a scene preset. Author the requested machine,
materials, bearings, shafts, cutaways and controls yourself.

`spurGear({teeth,module,backlash,samples})` returns a CCW local XY `outline` and
pitchRadius, baseRadius, rootRadius, tipRadius. Standard external 20-degree
unshifted gears only, 20..160 teeth; default samples=12 (6..24), module=.001..1000.
backlash defaults to .04*module PER gear (tooth-thickness reduction). Use mPrism
for the outline; no convex hull. Tooth flanks follow actual involutes. Root lands
are circular with radial extensions, NOT manufacturing trochoid fillets.

`externalGearPair({teethA,teethB,module,backlash,samples})` returns first/second
gears, center `distance`, ratio, theoretical contactRatio and `phaseAt(angle)`.
Centers are [0,0] and [distance,0]. phaseAt returns [driver,driven] CCW angles in
radians in that SAME local plane. Preserve handedness and add this angle to each
gear's local outline before mapping through the shared frame. Do not give each
gear a different mirrored frame, invent an extra half-tooth offset, or move the
centers away from the returned pitch-circle tangency. If the shafts are not
horizontal, rigidly transform the complete local pair, not individual angles.
Cache static outlines; do not regenerate them every animation frame.

`sliderCrank({radius,rodLength,side=1},angle)` returns pivot, pin, slider (2D),
rodAngle, stroke and displacement. The local guide is Y=0 through the pivot;
side=1 places the slider to the right, -1 to the left. radius>0 and rodLength
must be >=1.01*radius. Map BOTH returned pin centers and the guide into ONE world
plane. Derive rod ends, piston extension, crank pin and readout from this pose;
never independently approximate piston travel as a sine wave. Pin shafts and
bearing bores must visibly meet those exact centers. Stroke is twice the radius.

These helpers model ideal educational kinematics, not forces, friction, pressure,
manufacturing tolerances or steam thermodynamics. Show such quantities only if
there is an explicit, documented model. They throw on unsupported parameters.
Other mechanisms can use original code with equally explicit invariant checks.

Actual 3D contact is required, not merely a point on a 2D slot centreline. Put
mechanical XYZ positions, part thicknesses and axial intervals in the model;
consume those exact values in geometry and checks. For coaxial intervals
[a0,a1] and [b0,b1], overlap is min(a1,b1)-max(a0,b0): require a meaningful
positive engagement, not just touching end planes. For a pin in a slot, also
check halfWidth-pinRadius-abs(lateralOffset) against the intended clearance.
Sample both axial engagement and lateral clearance through the working cycle.
Journal intervals must pass through actual bearing bores; bearing seats and
their pedestals must join the foundation. An inset, floating contact dot, dashed
hidden line or assertion label cannot replace a connected solid or real cut face.

# Sectioned mechanisms and material routes

An opaque floor below every part, viewed from above, belongs in a separate
background layer. Do not globally depth-sort its large cap by its centroid;
that can paint the floor over machinery above it. For axial cutaways, partition
by the actual cut plane and preserve the appropriate region order. Keep rear
journal seats, frame members and their feet attached to the same foundation.
Removing a front frame is legitimate only when the remaining support is legible.
If the working material lies in an exposed axial plane, end the retained barrel
at that same plane: an offset face can project over a physically clear nip and
make a correct route look pasted onto the roller. An interior section must retain
the full local solid radius: do not reuse a chamfered physical end-face profile
for a cut through the middle of a barrel. Retain seated journal housings
and their structural path to the foundation whenever practical.

Split long piston rods at gland/head planes before opaque face ordering. The
solid piston body and rings must fit inside the actual bore throughout the whole
stroke; the rod must pass through an actual annular opening, not across its rim.
Both rod eyes, crosshead, crank pin and shaft bearings must use the same model
coordinates. A clevis needs two distinct bored cheeks with an actual gap receiving
the rod eye and one shared pin; a rod entering a solid block is not a fork joint.
A shaded solid cannot be replaced by a floating stack of stripes.

For a material-processing figure, define a continuous model-space route through
the actual working gaps. Check position/tangent continuity and the material's
thickness against the working surfaces. Render round incoming stock and a
visible flattened ribbon where appropriate. Do not use a diagonal guide line as
substitute for the processed material. Beds, chutes and trays must meet the route
and their supports; describe intentional omissions in a readable HTML legend.
A finite moving stalk need not fill the whole route simultaneously: mark its
leading tip and distinguish any faint route guide from actual material. Show its
progress with real model state rather than changing a view toggle to advance time.
