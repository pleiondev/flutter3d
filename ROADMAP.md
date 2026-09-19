# Roadmap

Revised 8 September 2026, and again on 11 September, off the calendar, because
the tooling decisions below changed what the quarter is for and waiting two
weeks to say so would have been the quiet kind of move this file forbids. It is
revised next on 28 September, then on 26 October and 23 November, and the
quarter it describes closes on 27 December 2026. Those dates are when this file
is rewritten, not when the work is due: a plan that is only rewritten when it
succeeds is a plan nobody can read.

Touched on 19 September as well, and only in *Where it stands*: three
paragraphs there described a tree that has moved, and a roadmap wrong about
the present is not worth reading about the future. *Committed* is as the
11 September revision left it and is rewritten on the 28th, when most of it
will be found finished. What comes after it is written down already, as
[`doc/engine-gap-analysis.md`](doc/engine-gap-analysis.md): what the engine
lacks for a space game, a ski slalom and an open world, in the order the owner
chose on 19 September.

**What has already shipped is not here.** It is in each package's
`CHANGELOG.md`, beside the version that carries it, which is the one place it
cannot drift — a roadmap that also tried to be a history would end up wrong
about both halves. This file is only the part that has not happened yet, plus
an honest paragraph about the state of the tree it will happen in.

Two tiers, and only two. **Committed** is what the quarter is for. **If the
committed work lands on time** is what follows immediately after, in the order
written, and it moves up or out on one of the revision dates above rather than
quietly.

## Where it stands

- [README](README.md) — what each package owns and how to run the games.
- [ARCHITECTURE.md](ARCHITECTURE.md) — why the layers are cut where they are.
- [CONTRIBUTING.md](CONTRIBUTING.md) — the conventions, including the one that
  a test is written by breaking the code it covers and watching it go red.
- [flutter3d.pleion.dev](https://flutter3d.pleion.dev) — guides, tutorials for
  each genre, and the generated API reference.

The engine renders through four backends behind one hardware contract —
Impeller, WebGL2, WebGPU and a software rasteriser — four games of different
genres run on it, and the structural scans that hold the layer rules pass.
Strategy, which was a package with a bot and a match that plays itself, is a
game with a demo in a browser. The model editor runs at
[models.pleion.dev](https://models.pleion.dev).

**0.7.0 is prepared and not published.** Thirty-three packages carry the
number; [`doc/boundary-0.7.0.md`](doc/boundary-0.7.0.md) says which names end,
which begin and which import lines change. Publication is held, by the owner's
decision, until five to ten people have walked the modeller's tutorial against
a clock.

**`main` has been red, and the badge in the README is telling the truth.**
It was red for the three causes below, and after they were fixed it stayed red
for three more, none of them in the code either: a check for plain Dart packages
that handed every one of them a Flutter plugin through an override, a job that
stopped at `gltf_validator --help` because that prints its usage and exits 1,
and an analysis of the two services under `cloud/` that nobody had resolved on
that runner. Those are fixed on the release branch, and no run has confirmed it
yet, so the sentence at the end of this paragraph still holds. The first three
were named when this file was written, and were fixed in that wave of work. The track generator wrote a lap length with the full
mantissa, so regenerating the file did not reproduce the committed one. The
macOS job never built the example's shader bundle, so a job that had all the
code failed for want of one script. And a table of libm's known answers was
recorded on one machine, then met a second and a third that round differently
in the last place. None of the three is the simulation being wrong: a step
still asks no machine for an answer, and the determinism it promises held
through all of it. What was red was the instrument. Until green runs stand in a
row, believe the badge and read this paragraph for the reason.

**The quarter is over-full, and the 11 September revision made it more so.**
Two tooling sections joined *Committed* without anything leaving it. The order
inside them is the order they are cut in if the 28 September revision finds
the calendar short, and the asset build is the one that stays.

## Committed

### A green main, and a release train

The three causes above are fixed at the root rather than pinned: the portable
maths gains the transcendental functions the parity test needs, the table of
known answers is deleted rather than extended, state digests are recorded on a
second operating system and committed beside the first, and the macOS job calls
the shader build like every other job does. A red `main` blocks a merge, and
that sentence goes into `CONTRIBUTING.md` where a contributor meets it.

Alongside it, an Impeller machine of my own runs the golden and conformance
suites nightly, because those are the two things ordinary CI cannot run and
therefore the two that rot unwatched.

*Acceptance: three green runs in a row, state digests recorded on two operating
systems rather than one, and a nightly run against real hardware whose result
lands in an artefact rather than in somebody's memory.*

### The editor, and an agent that drives it the same way

One application in which a level of any of the four genres is built and a
material is edited, and in which an agent does the same through an MCP server.
The rule that makes it possible is that every edit is a command object, and
that both the user interface and the MCP server call only those commands. An
agent that edits the document by a second path is an agent whose work cannot be
undone, and undo that is right for one of two callers is worse than no undo.
How a command is taken back is the document's business rather than the
command's — the level editor keeps a snapshot per step, and the modeller keeps
a journal of the values an edit replaced, which phase 0 measured at two per
cent of a snapshot.

The command core lives in its own package with no Flutter in it, for the same
reason the simulation does: it can then be tested the way the simulation is
tested, and the editor cannot quietly become the place where engine decisions
are made. Dragging an object moves the object rather than the camera, marks in
a level become one thing with a preset and fields instead of three kinds of
spawn point, material parameters carry hints so the inspector is built from the
format rather than from a hand-written form, and a Play button runs the genre's
simulation inside the editor and restores the document from a snapshot when it
stops.

*Acceptance: a level for each of the four genres built from an empty document
without hand-editing JSON; four project templates in the new-project dialog
rather than two; an agent-driven scenario replayed in CI and diffed against a
reference document; and zero changes inside the engine's own sources made for
the editor's sake, apart from the material hints.*

### A modeller, and the same agent driving it

One application in which a model is opened, its mesh edited and its material
set, and exported as something a game here loads without a warning — and an MCP
server offering the same commands to an agent, the way the level editor already
does for levels.

The vocabulary it needs came out of the engine first: `flutter3d_core`'s
geometry and formats libraries hold `MeshData`, the shape generators,
`ModelDocument` and the decoders with no Flutter SDK behind them, because a tool
a host starts with `dart run` cannot resolve one. They were two packages of
their own when this was written and were folded into the core since. Above them sit `flutter3d_mesh` — half-edge topology, which is
what a `MeshData` has already thrown away — a document layer with a command per
edit, and the application.

What phase 0 measured, and what it changed: a million triangles on macOS costs
one millisecond of `render` and nothing of the frame, while a thousand draw
calls costs twenty-five — so the budget a project carries is objects rather
than triangles. Re-uploading an edited mesh every frame is 1.2 ms at 200 000
triangles, so partial buffer overwrite is not phase-1 work. Picking through a
triangle BVH is microseconds against milliseconds for a scan, so it stays on
the CPU. History as a journal of previous values costs two per cent of a full
copy where chunked copy-on-write costs a hundred, so the mesh is a flat array
and a log. Under `--wasm` the application does not start where the same
revision in JavaScript does, so the browser build is dart2js and the reason is
being chased rather than assumed.

*Acceptance: a Khronos model imported, a face extruded, a base colour and a
texture set, exported as a GLB that this repository's own loader reads without
warnings and glTF-Validator accepts; the same run driven by an agent over MCP
and diffed in CI against a reference project; the editable mesh holding its
invariants over five hundred random operations; and the application built for
macOS, the browser, Android and iOS.*

### Assets that build themselves

Today a new project reaches its first frame through two manual steps a
newcomer has no reason to guess: a shell script that builds the shader bundle,
and a converter that lives in the engine's `tool/` directory where `dart run`
cannot find it. The first of those is also what turned the macOS job red. Both
go into a build hook. `dart run flutter3d:init` writes the hook and the one
pubspec entry it needs, and from then on `flutter run` converts glTF, GLB and
OBJ sources into the `.f3d` container, compresses their textures into KTX2 with
full mip chains in the block family each target reads, and builds the shader
bundle. The same code is `dart run flutter3d_build:convert` for anybody who would
rather run the step by hand or from another build system.

A hook runs in plain Dart, so everything it calls has to live below Flutter:
the KTX2 container and its transcoder move out of the engine into
`flutter3d_formats`, where the decoders already are. The texture encoder the
games section used to promise is this section's encoder. Data assets are not
on the stable channel of Flutter 3.47, so the hook writes into a generated
directory that the pubspec lists; a spike on all four platforms confirms that
before anything is built on it.

*Acceptance: `flutter create`, `flutter pub add flutter3d` and `dart run
flutter3d:init` reach a first frame with a textured GLB on macOS, the browser,
Android and iOS with no script run by hand; a converted model compares equal to
decoding its source with `document_compare`; a second build with no source
changed converts nothing; and the quickstart page loses its shader step.*

### The editors reach the running game, and an agent sees the frame

In the order these are cut in, last first.

A diagnostic MCP server beside the two document servers, for the question an
agent otherwise answers by guessing: why is the frame wrong? A screenshot of the
viewport and of the window in both editors; debug views of normals, depth,
shadow cascades, overdraw and texture coordinates; the output of any pass in
the frame graph and the HDR value of a pixel in it; and a scan that names the
first pass producing a NaN or an empty target. Every server keeps stdio for CI
and gains attaching to an editor that is already open, over loopback, so the
person and the agent are looking at one document rather than two copies of it.

Then the desktop editors run the project itself: a device picker, a build
configuration, hot reload and restart through the VM service, and the console
in a panel. Saving a model in the modeller or a texture anywhere replaces it in
the running game without a restart. That was on *Not doing* until 11
September, on the grounds that Play covered the need; it does inside the
editor, and does nothing for the game on a phone, which is where a material is
finally judged. Levels stay out, because a replay has to survive the swap and
nobody has worked out how. The browser editors cannot start a build, and do not
pretend to.

Then one editor shell in its own package, used by both applications: docking,
a command palette over the same commands the MCP servers call, a console, a
history panel and an asset browser. The applications stay two. What they
stop being is two separate implementations of the same panels.

*Acceptance: an agent over MCP names the pass that turns a deliberately broken
normal map black; a model saved in the modeller appears in a demo running on a
phone without restarting it; an agent attached to an open editor makes an edit
the person watches happen; and both applications built on the shared shell,
with the palette and the history panel coming from it.*

### Strategy as the fourth genre

The strategy package becomes a game, which means it first becomes a citizen:
snapshots, an input tape, deterministic dice and the entity world, the same as
the other three, so a match replays to the bit from its recording rather than
from a second run. Then combat — worker, shooter and tank, an attack order,
damage, death and a bot that builds as well as spends — and a military victory
beside the economic one. Then fog of war as a rule of the simulation rather
than a shader trick, with picking so a click selects a unit instead of ordering
the whole crowd.

The demo grows a heads-up display, touch controls, and the platform
configurations the other three demos already have.

*Acceptance: a fourth genre with snapshots, an input tape and a playthrough in
CI that beats the bot on a fixed map; the demo running on desktop, web, Android
and iOS; and the fourth game playable in a browser beside the other three.*

### Rendering: the rest of the light track

In the order of what costs least for what it returns. Per-object light lists
first, because eight lights is a ceiling on the scene today and the night maps
a strategy game wants are the first thing that hits it; light channels beside
them. Then colour grading through a lookup table, a filmic curve, physical
light units and the glTF punctual-lights extension, which are cheap and change
every screenshot. Then radial pulses; then a cheap wave that removes a choice a
game should not have to make — alpha hashing so particles stop fighting each
other, a five-tap disc filter for soft shadows, and a fast approximate
antialiasing pass in the frame graph, so a game no longer has to choose between
antialiasing and screen-space effects. Projected decals are the expensive item
and come after all of it. Compressed sections in the model container, and
readers for the mesh-compression extensions and texture transforms, close the
quarter: they are the first wall somebody hits with an asset made elsewhere.

*Acceptance: eight lights on an object with hundreds in the scene, where the
scene holds eight in total today; a golden image in each of the three backends'
sets for every item; and the architecture document rewritten in the same
direction as the code, not after it.*

### Terrain, triangle meshes, and animation that adds

Two collision shapes are missing and both are needed by games that already
exist: a heightfield, so a strategy map and a racing circuit can be ground
rather than boxes, and a triangle mesh, so an imported model can be collided
with as itself. Both land through the same three places in the collision code,
and the known trap — filtering the interior edges where triangles meet, so a
character does not catch on a seam — is where the risk in this track is. A
capsule stops being swept as a box on the way past, and the slope limit stops
being a constant.

Animation has the additive layer over a reference pose since 2026-09-17 —
`AnimationLayer.blend` with `AnimationClip.referenceTime`, which is where the
reference frame lives because glTF has nowhere to put it. What is left of this
is the small stack of push, blend and add operations around it, which is what a
recoil is, and what a graph editor would have been an expensive way to express.

*Acceptance: six collision shapes rather than four, with the heightfield and
the triangle mesh answering sweeps and rays; a capsule swept as a capsule; a
slope limit that is a setting rather than a number in the source; a parity file
proving the new sweep agrees between a virtual machine and a browser; and a
recoil in the shooter driven by an additive layer.*

### Backends and the platforms under them

A WebGPU spike comes first and answers one question: does the hardware contract
assume anything about OpenGL that a fourth backend would have to break? The
answer is due on the first revision date, because if it is yes the cost is a
change in three backends rather than one, and that is a decision to make in
September rather than in December.

Upstream work runs beside it on its own clock, because a pull request against a
graphics engine is reviewed on somebody else's calendar: capability getters
first, then mipmap generation, then storage buffers, which are the foundation
under every compute-dependent technique this engine does not have. Android and
iOS builds join CI, which is where the missing application identifiers, the
signing configuration and three games sharing one icon get found.

*Acceptance: the spike's answer by 28 September; debug builds of four demos for
Android and iOS in CI; at least two merged upstream pull requests and one
open.*

### Measurement, so the next decision is made on a number

A frame profiler with no interface: per-pass counters for time, draw calls,
instances, triangles and pipeline switches, gathered from the timeline marks
that already exist, exported as a trace file keyed by the replay tick that
produced it. Then a baseline in CI — a stress scene on the software backend,
where the number is stable because there is no driver in it — so a change that
doubles the draw calls says so in the pull request rather than on a phone.

And the one number a newcomer actually feels: the time from installing the
tooling to a first drawn frame, measured by a script on a clean machine and
published.

*Acceptance: a trace file per replay tick; a draw-count baseline asserted in CI
on the software backend; install-to-first-frame measured rather than estimated,
with a target under three minutes.*

### The games, in front of people

Three games built for the web and put where they can be played without an
install, then the fourth when it exists, with their textures compressed by the
asset build above rather than by a step somebody has to remember. Two releases
— one at the middle revision date, one at the quarter's close — with the
unreleased section of each changelog kept as the work happens rather than
written at the end.

*Acceptance: four games playable in a browser from the site; the assets of all
four compressed by the asset build; two releases tagged, one on each of 26
October and 27 December.*

## If the committed work lands on time

In this order, and only in this order.

1. **WebGPU as a full fourth backend** — the same shape as the WebGL2 one, with
   shader translation done at build time rather than in the browser, a fourth
   set of reference images, and the conformance contract passing in full. The
   spike decides how much of this is real; the second revision date decides
   whether it stays in the quarter.
2. **Two players in lockstep** — a transport package, input frames exchanged
   per tick over a WebSocket, a relay server small enough to self-host, and a
   digest trail so the first tick where two machines disagree can be named
   instead of guessed at. The determinism this rests on is already proven and
   already recorded; what is missing is the network, which is the part with no
   test that can prove it in advance.
3. **Soft bodies past the first phases** — the solver and its collisions are
   the committed part; the GPU branch, cutting, and a demo are here.
4. **Native gamepad and pointer capture on Windows and Linux** — both report
   honestly that they are unsupported today, which is the only reason "desktop"
   currently means macOS.
5. **Clustered light assignment** — and only if the per-object measurement asks
   for it. A technique adopted without a measurement is a technique nobody can
   remove later.
6. **The editors and models.pleion.dev** — opening, saving and placing a model
   from the account in the desktop editors as well as the browser ones, which
   needs a sign-in a native application can hold where a browser holds a
   cookie.
7. **Golden images from real GPUs in CI** — Impeller on a macOS runner and
   WebGL2 and WebGPU in Chrome, held to the same reference images the software
   backend draws, so a difference between a driver and the contract is caught
   in a pull request rather than on the nightly machine the morning after.
8. **Agent skills for people using the engine** — its idioms and the traps that
   fail silently, lighting and post-processing that read as deliberate, and
   performance, beside the skills already written for working on the engine.
9. **A guide per subsystem with a live demo in it, and an examples
   application** those guides point into, beside the genre tutorials rather
   than instead of them.

## After this quarter

Named here so that they are not mistaken for forgotten, not because a date has
been chosen for them.

A command-line tool whose `doctor` diagnoses the three usual causes of a black
screen, each of which currently costs a newcomer an evening. A server that
verifies a run by replaying it, which the simulation being plain Dart already
makes possible and which no service without your simulation can do. The file
formats specified in their own repository, with an exporter from a modelling
tool — the most underrated lever available, because content produced for a
format decides an engine before anyone benchmarks it. A level editor in the
browser. A certification badge for a backend somebody else writes against the
conformance contract. And a 1.0: one version across every package, an API
freeze two months ahead of it, and a written support policy, because that is
what a team asks before taking a dependency.

Prefabs over the level documents: a model or a group placed by reference, from
a file or from the account, without a second scene format. Hot reload of
levels, once a replay has a way to survive one.

Three items came off *Not doing* on 11 September and wait here rather than in
the quarter. **Flutter widgets on 3D surfaces**, because an engine for Flutter
that cannot put a widget into a scene leaves out the one thing no other engine
could offer. **Rigid bodies with rotation and joints**, because three genres
shipping without them showed they do not block those three, and a vehicle, a
ragdoll or a stack of crates is what the next game reaches for first. And
**temporal antialiasing with motion blur**, because the cheap wave above
settles a still frame and cannot settle the shimmer of a moving camera.

## Not doing, and why

- **Comparison tables against other engines.** The question this project
  answers is whether a game reaches players, and a table costs weeks of
  methodology before it says anything about that.
- **Node-graph materials that compile a shader.** There is no shader
  compilation at runtime here, and a graph that cannot produce a new shader is
  a picture of one. What the modeller gets instead is a **fixed set of nodes
  that bakes into texture slots** — mix, tint, tile and mask over images that
  already exist, evaluated into the maps a material already samples. That is a
  texture compositor rather than a shader graph, and calling it by its own name
  is the point.
- **An entity-component renderer.** The scene graph is not the bottleneck any
  profile has found, and rewriting it would spend the quarter.
- **Order-independent transparency**, beyond the alpha hashing named above.
- **Static and dynamic node separation, and refitting the culling tree.** Worth
  doing when a scene is large enough for it to show; no scene here is yet.
- **Terrain clipmaps.** The heightfield above is collision and gameplay; making
  it a rendering system is a separate quarter.
- **Quality presets as an API.** They would be assembled from knobs whose
  spread is about to change; a preset written now is a preset rewritten in
  three months.
- **Compute-dependent techniques.** The only item on this list whose absence is
  the platform's rather than a choice, and the upstream work above is the
  thing that would change it.

## How this file changes

On each of the three revision dates, every item is in one of four places: done
and gone to a changelog, still committed, moved down a tier, or moved to *Not
doing* with the sentence that says why. Nothing moves by being left unmentioned
until December, because a roadmap whose items expire in silence teaches its
readers to ignore it.

Numbers in this file are the ones the acceptance lines name, and they are
recounted when they are written rather than copied forward. The counts that
describe the repository as it is — how much of it is tested, how many scans
hold it together — live in the README and in `ARCHITECTURE.md`, where a scan
compares them with the tree on every run.
