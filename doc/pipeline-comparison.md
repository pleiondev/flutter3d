# The whole pipeline, against flutter_scene

*Established 2026-09-18 by a ten-dimension survey: 21 agents, 975 tool calls,
3.1M tokens, 32 minutes. Every dimension was surveyed once and then handed to a
refuter told to break the claims rather than confirm them, with "I could not
confirm it" counting as refuted. 128 claims went in, 19 came back dead, and the
counts below are what survived.*

Pinned at `bdero/flutter_scene@77c7dbaae8963cfaf95922d171166a73507408e1`: 620
Dart files and 111 shaders under `packages/flutter_scene/`, which is around
0.23.0. The copy in `~/.pub-cache` is 0.20.0 and was used only to find file
names quickly; no claim here rests on it. Our side is this repository.

Postprocessing is not in here. It has its own survey at
`doc/postprocessing-parity.md`, and repeating it would have cost a dimension
that was better spent on something nobody had looked at.

## 1. The number, and then the shape of it

Of 128 surviving claims, 68 have us behind, 35 have us ahead and 18 level. Four
are things neither side has and three could not be settled. Of the 65 the
surveyors marked load-bearing, meaning a reader would change a decision over
them, 48 have us behind and 12 ahead.

That is a harsher answer than the postprocessing survey gave. What the ratio
does not say is where it falls: sorted by dimension, every claim we won is
about knowing a frame is right, and almost every claim we lost is about what a
frame can contain and how fast.

| Dimension | ahead | level | behind |
|---|---|---|---|
| Scene graph, transforms, instancing, LOD | 2 | 5 | 8 |
| Culling, sorting, draw submission | 2 | 1 | 9 |
| Materials and the shader system | 1 | 0 | 10 |
| Lighting | 2 | 1 | 10 |
| Shadows | 4 | 2 | 7 |
| Skinning, animation, particles | 6 | 2 | 6 |
| Frame graph and resource lifetimes | 4 | 2 | 3 |
| Backends and portability | 6 | 2 | 3 |
| Assets, import, texture compression | 2 | 2 | 8 |
| Verification | 6 | 1 | 4 |

The two dimensions we win are the two about the machinery around the picture.
The four we lose worst, materials, lighting, assets and culling, are the
picture itself.

## 2. What we are actually good at

`flutter3d_hardware` is a package whose pubspec depends on `vector_math` and
nothing else, with two structure rules refusing a graphics API or Flutter
anywhere in it. Behind it sit four implementations: Impeller through
flutter_gpu, WebGL2, WebGPU, and a software rasteriser in Dart. Theirs has two.
`gpu/impeller/_gpu.dart` is thirteen lines re-exporting `package:flutter_gpu`
verbatim, and `gpu/web/` is a genuine WebGL2 reimplementation of that API at
about 3600 lines. A search of all 1628 blobs at the pin for `webgpu` and `wgsl`
returns nothing, and their `gpu/stub/` throws on every member, so there is no
software path either.

That layer is worth having because a backend can be held to a contract before
anybody trusts it. `flutter3d_conformance` is 37 checks in two tiers across 23
files, and a backend runs them against itself. Their nearest mechanism is
`try { Scene(); } catch` to decide whether a GPU is present.

The visual baseline is in the repository, and four sets of it disagree
usefully: four directories of 44 PNGs each, with three sibling tests holding
CPU, WebGL and WebGPU against Impeller's, plus a coarser 16×16 luminance-grid
parity fixture. Theirs live in Argos, a hosted visual-diff service, and each CI
lane diffs only against its own history, so nothing on their side compares one
backend's pixels with another's. Forty-eight PNGs exist at the pin and every
one is an icon, a favicon or an example texture.

Our frame graph culls what nothing consumes. `FrameGraph.compile` walks back
from the frame's outputs and keeps only what they reach, then iterates a fixed
point over hard reads. Their `RenderGraph.execute` runs its passes in insertion
order, and its own class doc says it does not cull unused passes. The earlier
postprocessing survey claimed that; this one confirmed it at the pin.

Animation is the one content dimension we win. We support the full glTF
interpolation set including `cubicSpline`, against their own doc's admission
that only linear is supported and that `CUBICSPLINE` samplers keep their
tangents and are ignored. Our layered player with masks beats their flat
weight-scaled blend, and we have a static/dynamic split for point and spot
shadows that their source marks `TODO(point-shadow-cache)`.

Every one of these answers "is this frame correct" rather than "can this frame
contain X". That is the position we occupy, and it is worth occupying honestly.

## 3. Where we are behind, worst first

### The picture cannot contain things theirs can

Eight lights per draw, as a compile-time constant on both the Dart and GLSL
sides. Theirs subdivides the frustum into froxels with exponential depth
slices, 255 lights per froxel, and the fragment loop runs the froxel's exact
count, so under clustering there is no per-object cap at all. A search for
`froxel|clustered|forward+|tiled light` in our Dart outside tests finds one
aspirational comment.

**Corrected 2026-09-18, on the way into `gfx-74n`.** "Eight lights" is the cap
on *one draw* and was read here as the cap on a scene, which it is not:
`gfx-12n` already picks the eight that reach each object, so a night map may
carry two hundred torches and every object is lit by its own eight. What the
cap actually costs is written down in `Renderer._drawLightsFor` and is narrower
and sharper than this paragraph says: a surface large enough to touch many
lights at once — a ground plane whose bounding sphere reaches every torch —
scores them all at distance zero and keeps the eight brightest, and an
instanced crowd spread across a map shares one list chosen for the whole batch.
`RenderSettings.lightFadeBand` exists because the eight that reach an object
change as it moves. So the gap is real and it is not "the picture cannot
contain more than eight lights"; this is the second premise in this document
that named a missing feature we had, after the frame instrument below.

Three light types against their four: theirs adds `RectAreaLight`, integrated
with linearly-transformed cosines off the `ltc.bin` they ship.

No runtime global illumination. Theirs has an irradiance field of DDGI shape,
with octahedral probe tiles, gutters and depth moments, plus SH probes and
environment volumes. Our indirect diffuse is the environment's roughest mip or
a baked lightmap, and the baker lives in a game package rather than in the
engine.

No Gaussian splats. They have `lib/src/splats/` with a codec, a sorter and a
native/web sort service. A search of every `.dart` and `.glsl` in `packages/`
for `gaussian|splat` returns two false positives, both comments about
something else.

No contact shadows. Theirs marches eight steps toward the light against a
linear-depth buffer. The word "contact" in our shaders means contact
*hardening*, the PCSS blocker search, which is a different thing. It is exactly
the kind of grep hit that makes a survey of our own side flatter us. *Built
since, as `gfx-76n`: `post/contact_shadow.frag` and a resource of its own, with
its own strength in the composite so the occlusion being off does not decide for
it.*

**No alpha-masked shadow casters**, which is the one a reader will see first.
`shadow_depth.frag` ends in `frag_color = vec4(gl_FragCoord.z, 0.0, 0.0, 1.0)`
unconditionally, and the shadow pass has no alpha, cutoff or mask anywhere in
it. Every foliage card, fence and grate on our side casts the shadow of its
whole quad. Theirs resolves a masked depth-only fragment shader per caster.

### The frame costs more than it should

We cache an exact world AABB per mesh and then cull against a sphere.
`MeshNode.worldBounds` is transform-versioned and maintained, and nothing in
the culling path reads it: the render list takes centre and radius and calls
`intersectsWithSphere`, and the scene BVH is built over four-float spheres. We
pay for the tighter volume and spend the looser one.

The BVH only runs above 2048 meshes (`bvhThreshold = 2048`); below that, a
linear scan. Theirs uses a Morton-curve BVH over world AABBs for every cull at
every scene size, and distinguishes structural dirt from a moved item so it can
`refit()` in one forward pass. Ours has no refit, only a rebuild. Theirs also
caches a subtree AABB per node with an upward invalidation walk, so a whole
branch outside the frustum is rejected before the BVH runs; we have exactly one
layer.

Every `worldMatrix` read walks to the root with no early-out, and
`visibleInHierarchy` walks too, from seventeen call sites. Theirs is a flag
test against a clean cache. The survey compared the write sides and called it a
win; the refuter priced the reads, and a frame is made of reads.

A hundred `MeshNode`s sharing one geometry and one material are a hundred
draws. Theirs merges consecutive opaque records into one instanced draw when
pipeline, geometry, material, fade and light slice all match.

The cascade loop walks every mesh in the scene for every cascade and rejects
only on visibility and the casting flag, so there is no shadow caster culling
at all. Theirs frustum-tests each caster against the tile it is filling. Nor do
we split static from dynamic casters for the directional cascades: every
cascade is redrawn from nothing every frame, where theirs keeps a persistent
static tile per cascade with a slack factor so the camera can move inside it
without a re-render. We do have that split for point and spot lights, which is
why that row is ours and this one is theirs.

Skinning is recomputed per primitive per pass. `Skeleton.update` allocates a
fresh `Matrix4` per joint on every call and is called from mesh encoding, the
pick pass and the shadow pass. A character split across four materials
recomputes and re-uploads the same 64 matrices once per primitive per pass, in
a class whose own doc says the array was preallocated to avoid exactly that.

### The ceiling is lower than theirs

A material cannot supply a vertex stage. Theirs has a `.fmat` material
*language* with a parser, an AST and an emitter, a `vertex { }` block, and
three generated vertex variants per material. Ours is JSON data: a lighting
model name, numbers and texture slots, with the vertex stages required by fixed
name in the renderer. Vertex displacement, an ocean, wind and a per-material
morph hook are all outside what we can express. A ceiling like that does not
show up as a row in a feature table.

We have no shader variants either: one fragment shader per lighting model,
chosen by `Material.lighting` and nothing else, with no `#ifdef` permutation
axis anywhere in our shaders. Theirs resolves a variant per draw across four
shader fields per material.

Uniform binding is untyped by contract, every uniform a float vector or matrix
with integers and booleans encoded as floats. Theirs builds one persistent
`ByteData` per material from the reflected block, with a typed slot and a
default per declared parameter. And what a shader declares versus what the
engine binds is hand-maintained on our side: `LightingModel` carries a row of
`usesX` booleans somebody keeps in step, where theirs decides liveness at emit
time and says in the shader source why, because a declared-but-unread resource
has backend-dependent liveness.

### Assets arrive in worse shape

The automated build never compresses a texture. `buildAssets` calls
`convertOne` with no `textures:` argument, so it takes `TextureFamily.auto` and
emits PNG or JPEG inside `.f3d`. The `--textures bc` path everyone argues about
is a hand-run CLI flag most users never reach. Theirs cooks block payloads with
mips through the build hook, and builds the mip chain unconditionally where we
write one level.

Our KTX2 parser throws on UASTC and on zstd by name. Theirs decodes UASTC to
RGBA8 or repacks it straight to ASTC, and carries an 864-line pure-Dart zstd
decoder. A cooked texture is device-specific on our side, since we bake one
final GPU format at CLI time; theirs cooks to a device-agnostic 4×4 block
intermediate and transcodes at load against what the device reports.

We detect `KHR_draco_mesh_compression`, warn, and skip the primitive. They have
a complete pure-Dart decoder: edgebreaker, corner table, rANS, fourteen files.

### Nothing renders in our CI

Four jobs, none with a GPU, and the `check` job's own header says so. Theirs
has seven render lanes on every pull request, on merge and nightly: Linux under
Mesa, Android GLES on an emulator, Android Vulkan, web, Windows, macOS and iOS,
uploading PNGs to a visual-diff service. Our committed goldens are the better
artefact and nothing in CI re-renders them.

Two platforms make it worse. Their pubspec declares windows and linux; ours
ship neither, in any of the ten apps. A dimension titled "what runs where"
spent itself on backend counts while the reader's question is which platforms
they can ship.

## 4. What nobody surveyed, and should have

The completeness critic went through the pinned tree against ours and found six
subsystems that fell between the ten dimensions. Three are places where we have
nothing at all.

**Frame capture, though not counters, and the critic got this one wrong.**
The completeness critic reported that our counters are pass-local and never
aggregated, and that we have no instrument to count with. That is false, and
it is false because the critic grepped for their names: `RenderStats`,
`frameStats`, `GpuTimer`. We have `FrameResult.passes`, a record per graph
node carrying time, draws, triangles and pipeline switches, filled by
differencing counters either side of every `node.execute` at
`renderer.dart:3095`, plus a `MetricsOverlay` in the modeller that lists them.
`gfx-01n` built it and its own row records the three wrong numbers it found on
its first run.

What we do lack is the other half. Theirs has a one-frame graph capture that
copies every texture each pass wrote, so transient reuse cannot overwrite the
evidence, and an editor panel that shows it; ours reports times and counts and
no pixels. It also has a `TODO(gpu-timing)` naming a Flutter issue for
timestamp queries, which neither side has. So the gap is capture and GPU
timing, not counting.

**Memory pressure.** Theirs wires `releaseTransientRenderTargets()` to platform
memory pressure and documents that the pool otherwise settles at the high-water
mark of every attachment shape any frame needed. Ours has the same high-water
behaviour and no shed at all: a grep for memory pressure or budget in the
engine returns nothing. On a phone that is a crash class.

**Accessibility.** Theirs publishes a node to screen readers as a semantics
element of the enclosing view, with a focus rect projected through the camera,
traversal order, occlusion hiding and platform-invoked actions. Ours: two hits
for the word in comments. Nothing makes our 3D content reachable to assistive
technology.

The other three, picking and input, Flutter/UI integration in both directions,
and baked indirect light, are two-sided comparisons worth writing that were
simply out of scope. On picking we have something they appear not to: a GPU id
pass beside the CPU raycaster.

## 5. What this kind of comparison structurally cannot say

Their repository was created 2024-02-01 and has 783 stars, 17 contributors with
an outside tail, and 36 pub.dev releases. Ours was created 2026-08-08 and has
27 stars, 2 forks, 958 commits and 7 releases. Both are effectively one author;
only one has two and a half years and other people's commits in it.

Their pubspec floor names a Flutter issue as the reason for its version,
because the engine's author is the Flutter GPU author and moves the SDK to fit
the engine. We consume the same SDK from outside, and the HAL with four
backends behind it exists precisely because we cannot. That is a dependency
risk on their side and a maintenance tax on ours, and it is probably the single
fact most likely to decide a choice between us.

The two projects also answer "what went wrong" differently. Their posture is
observability: render stats, graph capture, memory report, a blank-frame
diagnostic test, CI lanes that render. Ours is verifiability: four-backend
conformance, committed goldens, a CPU re-implementation of the lighting maths
that exists to disagree with the GPU ones. A feature table scores neither, and
a reader is choosing between "I can see my frame" and "the frame is proven
identical on four backends".

Then there is how much of the thing you have to take. Theirs is one package
plus optional satellites; ours is 27 published packages of 36 in the workspace.
Partial adoption is how these decisions actually get made and no dimension
asked about it.

## 6. What the refuters killed

Nineteen claims of 128 did not survive, and they cluster. The materials
dimension lost five of eleven, the highest rate, and every one was a claim
about our side that a grep supported and a reading did not.

Two features we "have" turned out to be words in comments. Contact shadows and
decals each return several confident-looking hits in our repository and have no
implementation. Our doc comments discuss features hypothetically and at length,
so a surveyor who greps our side and reads theirs gets a systematic bias in our
favour. That is the inverse of the failure the brief warned about and it is the
one to watch for next time.

One correction runs the other way. The postprocessing survey recorded that
flutter_scene has a depth prepass. At the pin, `DepthPrepass` exists and its doc
comment claims it primes early-Z; the code does not, since it is scheduled only
when an effect asks for depth or normals. Neither side has a depth prepass for
early-Z, and that row in the earlier document should be read with this next to
it.

Where this document is still most likely flattering us, in the critic's order:
any claim whose evidence is a path without a line and a symbol; the test-count
comparison, since file counts flatter whoever writes smaller files and their
single smoke test is 724 lines of semantic assertions running on six GPU
stacks; "four backends" as a portability win, given the per-backend
`UnsupportedError` counts and the two desktop platforms we do not ship; and
every lighting or shadow row scored ours, given what section 4 puts on the
table.

## 7. What the plan does about it

`doc/model-editor-plan.md` carries 25 rows from this survey, as phases G4 and
G5 of the `gfx-` track. The owner's decision on 2026-09-18 was to fix what is
broken and lift the two ceilings, and not to chase feature breadth, because
verification is where this engine is ahead and a second copy of theirs would be
worse at both.

G4 is the cycle. It opens with ten rows that need no new machinery, because
they are work we already do and discard: `gfx-60n` alpha-masked shadow casters,
`gfx-61n` culling against the AABB `_refreshBounds` already fills, `gfx-62n`
the BVH at every scene size with a refit, `gfx-63n` caster culling inside the
shadow passes, `gfx-64n` skinning once per skeleton per frame, `gfx-65n` a
world transform that does not walk to the root on every read, `gfx-66n` subtree
bounds, `gfx-67n` cross-node batching, `gfx-68n` a static tile for the
directional cascades, and `gfx-69n` an asset build that compresses and writes a
mip chain.

Then the instruments and the reach: `gfx-70n` a frame capture with pixels in
it, `gfx-71n` shedding transient targets under memory pressure, `gfx-72n` a CI
lane that renders, `gfx-73n` Windows and Linux. Then the two ceilings,
clustered lighting first: `gfx-74n` and `gfx-75n`.

G5 holds the breadth rows anyway, ordered after the ceilings. Four of them were
proposed for declining and kept by owner decision, which is the better outcome:
a declined row somebody can read beats an absence somebody has to notice.
`gfx-80n` Gaussian splats, `gfx-81n` a runtime irradiance field, `gfx-82n`
Draco and `gfx-84n` the material language each carry the reason they were
nearly dropped.
