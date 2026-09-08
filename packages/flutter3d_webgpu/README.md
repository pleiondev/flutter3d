# flutter3d_webgpu

`flutter3d_hardware` over WebGPU. The fourth backend, and the one being built.

**A device opens, a pass records, and a draw comes back as pixels.** What is
not here yet is a bundle handed over as bytes — `loadShaders` refuses and names
the file that will answer it — and six of the engine's own fragment stages,
which this implementation refuses for a reason worth reading below.

    final device = await openWebGpu(width: 960, height: 540);

Two barrels, and which one to import is decided by whether the importer runs in
a browser. `flutter3d_webgpu.dart` is pure Dart: the translation table and the
signature a draw looks a pipeline up by, both asserted on the VM in about a
second. `flutter3d_webgpu_web.dart` is everything that reaches for
`dart:js_interop` — the device, the encoder, the frame arenas and the hand-written
bindings under all of it.

The table came from `tool/webgpu_spike`, which drew a triangle through the
contract in a real browser to settle the two answers a table cannot settle on
its own — that a clip-space counter-clockwise winding is WebGPU's `"ccw"`
despite a framebuffer whose y runs down, and that the contract needs no
correction anywhere else. It is moved here unchanged, prose included, so that
what this package asserts is exactly what was measured rather than a retyping
of it.

## What WebGPU cannot say

Two of the fifteen blend factors come back null. OpenGL, Metal and Vulkan all
split the blend constant into a colour form and an alpha form, and `BlendFactor`
mirrors that split; WebGPU has `"constant"` and `"one-minus-constant"` and
nothing else. So `BlendFactor.blendAlpha` in the colour equation is a term the
hardware interface can ask for and this API cannot form. It is reported as
null rather than translated to something close, and the device will answer
`supportsBlendColor` with false — which the contract already asks a caller to
check.

## The shaders, and the two programs that make them

`lib/engine_shaders.dart` is generated and committed, the way the other two
backends' tables are:

    dart run tool/generate_shaders.dart

It reads the same manifest `impellerc` and the WebGL generator read, edits the
**declarations** of each stage's GLSL, and hands the result to
`glslangValidator -V --auto-map-locations` and then to
`naga --keep-coordinate-space`. Both must be on `PATH`; `tool/ci.sh`
regenerates the table and diffs it, so a stale table or a different compiler is
a failed build rather than a wrong picture.

Three things about that road are worth knowing before touching it.

**naga will not read a combined sampler.** `uniform sampler2D tex` compiles to
SPIR-V that `spirv-val` accepts and naga refuses with `invalid id %14`, naming
neither a file nor a construct. So each sampler declaration becomes a
`texture2D`, a `sampler` and a `#define` that puts them back together, and every
call site — 53 `texture()` and 11 `textureLod()` — passes through the macro
untouched.

**naga turns a vertex stage over unless told not to.** Without
`--keep-coordinate-space` the tail of every vertex entry point grows
`gl_Position.y = -(gl_Position.y)`. Nothing fails: the WGSL compiles, the
pipeline builds, and every scene comes back upside down.

**A varying's location is decided across the manifest, not inside a file.**
WebGPU does not link — two modules are compiled apart and joined by location
alone — so a shader that declares a varying of its own before its include would
shift one side of a pair and not the other, and draw the wrong picture with
nothing to say so. Locations are a function of the name, grouped into families
by which names ever appear together, because there are seventeen varyings and
sixteen locations.

## The six stages this implementation used to refuse

`textureSample` may only be called from uniform control flow, and six of the
engine's fragment stages — `Pbr`, `BlinnPhong`, `Lambert`, `Toon`,
`Reflections` and `Ssao` — sampled a texture under a branch the four
invocations of a quad need not take together: a light the surface faces away
from, a cascade that does not contain the fragment, a ray that has already left
the frame, a tangent too degenerate to build a frame from. naga accepted all six
and round-tripped them, so the shader pipeline was green while a browser refused
them, and the refusal arrived at the first pipeline built from one as `invalid
due to a previous error`, naming no line.

The cure was in the GLSL and it was two cures, chosen per site. The three
single-level render targets a lit scene reads under a branch — the cascade
atlas, the two point-shadow atlases, the surface buffer and the scene colour
the two screen-space passes march through — are now read with `textureLod` at
level zero, which is the level an implicit derivative was selecting anyway on a
texture that has only one. The normal map is not one of those: it carries a real
mip chain, so pinning a level there would have changed the picture, and the
sample is hoisted above the branch instead. `test/open_test.dart` now asserts
that nothing is refused at all, so a stage that reacquires the fault fails
rather than raising a count.

## Where the buffers of a frame live

The WebGL2 backend makes a `WebGLBuffer` for every transient binding and
deletes it when the pass ends — 1552 of them in one measured frame — and gets
away with it because a GL driver owns the fencing. WebGPU has an explicit
`destroy` and no such fencing to lean on, so this backend keeps one bump
allocator per kind of transient upload and rewinds it at `beginFrame`. That is
safe under a frame the GPU has not finished because `queue.writeBuffer` copies
into the queue's own staging at the moment of the call and schedules the write
*on the queue*: frame N's write, frame N's pass, frame N+1's write and frame
N+1's pass execute in that order however far behind the GPU is. An arena that
outgrows itself keeps the old buffer rather than freeing it, because a bind
group made earlier in the frame names it. `webgpu_resources.dart` is where the
argument is written out.

## Why half of it is pure Dart

Nothing in `webgpu_formats.dart` or `webgpu_pipeline_cache.dart` imports
`dart:js_interop` or `package:web`, so their tests run on the VM in about a
second, with no browser and no GPU. A typo in `"less-equal"` is then a failed
unit test rather than a browser refusing a pipeline at run time on a machine
that has a GPU, which is the worst place to find out — and the same split is
what lets the pipeline signature be asked whether two vertex layouts over one
stage pair are two pipelines, which is a question about a map rather than about
a driver.

---

Part of [flutter3d](https://github.com/pleiondev/flutter3d), an **independent
implementation** of a 3D engine for Flutter — not a fork or a binding of
another engine, and not affiliated with the Flutter team. Three switchable
rendering backends: Impeller via Flutter GPU, WebGL2, and a software
rasteriser. glTF, OBJ and `.f3d` loading, six lighting models, shadows, bloom,
skinning, animation, BVH culling and picking; a deterministic fixed-step game
layer with collision, navigation, positional audio, and gamepad and touch
input. Three example games — shooter, platformer, racing — each built on its
genre package: [`flutter3d_game_shooter`](../flutter3d_game_shooter),
[`flutter3d_game_platformer`](../flutter3d_game_platformer),
[`flutter3d_game_racing`](../flutter3d_game_racing). A new game starts from the
editor's scaffold, which writes one from a template: <https://flutter3d.pleion.dev/first-project/>.
Documentation: <https://flutter3d.pleion.dev>.
