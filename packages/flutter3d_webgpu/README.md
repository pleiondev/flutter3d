# flutter3d_webgpu

`flutter3d_hardware` over WebGPU. The fourth backend.

**A device opens, a pass records, a draw comes back as pixels, and the
conformance suite answers 33 of 33 against a live adapter in Chrome** — the same
list the other three backends are held to, run as an ordinary test file rather
than as an application somebody watches, because Chrome has a real WebGPU device
inside `flutter test`. Two of those thirty-three pass by *declining*, and each
decline is a capability this device says false to by name: the blend constant and
wireframe. All thirty-nine of the engine's stages compile, a bundle handed over as
bytes loads, a KTX2 texture in any family the adapter carries is sampled, and a
float target reads back as a picture.

    final device = await openWebGpu(width: 960, height: 540);

**A browser build does not open this backend unless it asks.**
`flutter3d_backend` opens WebGL2 in a browser and tries WebGPU first only behind
`--dart-define=FLUTTER3D_WEBGPU=true`; the engine's own example takes
`?backend=webgpu` in the URL instead, because a golden stand that serves
forty-three scenes from one build should not spend that saving on a define. The
default is not a verdict about WebGPU. It is that a probe able to call either
opener keeps both backends reachable and dart2js ships what it can reach —
376,649 bytes of `main.dart.js`, 14.9%, measured on `apps/flutter3d_demo_strategy`
— and that WebGL2 is the browser backend three shipped games have been looked at
on.

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

## What this backend declines, and why each no is a no

A refusal and a gap look identical from outside, so every one of these is a
declared capability rather than a method that quietly does nothing.

**The blend constant.** Two of the fifteen blend factors come back null. OpenGL,
Metal and Vulkan all split the blend constant into a colour form and an alpha
form, and `BlendFactor` mirrors that split; WebGPU has `"constant"` and
`"one-minus-constant"` and nothing else. So `BlendFactor.blendAlpha` in the
colour equation is a term the hardware interface can ask for and this API cannot
form. It is reported as null rather than translated to something close, and the
device answers `supportsBlendColor` false — which the contract already asks a
caller to check. Nothing in the engine, the games or the site builds one.

**Wireframe.** WebGPU has no polygon fill mode at all. A wireframe here would be
line primitives and an index buffer built for them, which is the renderer's
decision rather than a backend's — the same answer WebGL2 gives for the same
reason.

**Three formats with no spelling.** `a8UNormInt`, which WebGPU dropped in favour
of `r8unorm` plus a swizzle in the shader, and the two HDR ASTC layouts, which no
WebGPU feature exposes — `texture-compression-astc` unlocks the LDR blocks and
there is no second feature behind it. `supportsTextureFormat` answers false for
those three on every adapter there will ever be, and a loader leaves such a
texture out with a reason.

Four entries used to sit below these and no longer do, and all four corrections
are worth keeping.

**The block-compressed formats** were declined on the grounds that a WebGPU
device gets exactly the features it asked for and `create` asked for none of the
three families — a true sentence about the request rather than about the API.
They are asked for now, and the shape of the asking is the part worth
remembering: `requestDevice` handed a feature the adapter does not carry
**rejects the promise** instead of answering with a lesser device, so the adapter
is asked what it has and the intersection is requested. `supportsTextureFormat`
then answers from `gpuDevice.features` — what was granted — because a device may
be given less than it asked for, and a capability answering from a wish is how a
loader is told to upload a texture the browser will not take. Uploading one is
block arithmetic and not texel arithmetic: `writeTexture`'s `bytesPerRow` is a row
of *blocks* and `rowsPerImage` counts block rows, so an 8x8 BC1 level is two rows
of sixteen bytes. The conformance suite's compressed check stops declining itself
and draws a block of each family it finds.

**`readPixels` of a float target** answered null, and the contract names that
method as *the* way to read one: `readback` refuses a float format above every
backend and its own message says so. WebGPU has no format-converting readback —
`copyTextureToBuffer` hands over the bytes as they are stored, where
`glReadPixels` converts — so a float target is drawn into an eight-bit one by a
full-screen `textureLoad` pass and the copy is made from that. The price is a
pass and an allocation per call, which is why the eight-bit path is still a plain
copy. What that pass found is worth as much as the pass: **nothing in
`flutter3d_conformance` has ever asked any backend to read a float target back.**
Every readback in that suite is `r8g8b8a8UNormInt`, the one check that mentions a
float format asserts the *refusal* of `readback`, and a check added there would
fail on WebGL2 today, where `readPixels(RGBA, UNSIGNED_BYTE)` of an RGBA16F
attachment is an `INVALID_OPERATION` leaving a pack buffer of zeros and a future
that completes successfully with a black picture. So the promise is witnessed in
`test/webgpu_draw_test.dart` and the hole in the other backend is written down
rather than turned into a red build by this package.

`createCubeRenderTarget` answered null on the argument that a cube a probe draws
into is only useful beside a chain it can filter into — and the conformance suite
disagreed, because `supportsCubeTextures` answering true is read as a promise
that *a pass can name a face*, not merely that a sampler can read one. The suite
failed that check rather than declining it, which is exactly how a gap wearing a
refusal's clothes shows itself.

`supportsRenderToMip` then went on saying false beside the cube it had been
paired with, which by then described no missing work. Nothing had to be built to
lift it. WebGPU has no `generateMipmap`, and the engine never asks for one: a
reflection probe convolves its own chain, one full-screen pass per face and
level, and a colour target naming a face and a level is `baseArrayLayer` and
`baseMipLevel` on an ordinary 2D view here — the pass's viewport comes from that
view, so it covers the level rather than the texture without any arithmetic. The
proof is `probe-car`, recorded through this backend and landing on Impeller's
reference at nought of a hundred and seventy-two thousand eight hundred pixels.
A refusal that outlives its reason is worse than the gap it once guarded, because
nobody goes looking behind it.

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

## The six stages a browser used to refuse

`textureSample` may only be called from uniform control flow, and six of the
engine's fragment stages — `Pbr`, `BlinnPhong`, `Lambert`, `Toon`,
`Reflections` and `Ssao` — sampled a texture under a branch the four
invocations of a quad need not take together: a light the surface faces away
from, a cascade that does not contain the fragment, a ray that has already left
the frame, a tangent too degenerate to build a frame from. naga accepted all six
and round-tripped them, so the shader pipeline was green while a browser refused
them, and the refusal arrived at the first pipeline built from one as `invalid
due to a previous error`, naming no line. And one at a time:
`getCompilationInfo` reports the first fault in a module and stops, so fixing one
site revealed the next rather than shortening a list, and the count was known
only once it reached nought.

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

**That cure edits GLSL all four backends read, which is the widest change this
package has made outside itself.** What could prove it neutral is a recorded set
from a backend whose shaders are *compiled or translated* from that text —
Impeller's or WebGL2's. The software rasteriser's set came back byte for byte
identical and is not that proof: `flutter3d_cpu` draws from Dart transcriptions
written by hand, and says so at the head of its own files. Read a green run for
what it witnesses.

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
