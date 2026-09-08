# flutter3d_webgpu

`flutter3d_hardware` over WebGPU. The fourth backend, and the one being built.

**Nothing here opens a device yet.** What this package holds today is the
translation table — every enumeration the contract names, written as the
WebGPU string the specification spells it with, and the key a device will look
each draw's real pipeline up by — and the shaders: WGSL for every stage the
engine asks for, with the reflection a `GPUShaderModule` cannot be asked for.
The device and the encoder arrive in the waves that follow, and this package
exists ahead of them so that three branches writing into it do not each invent
a `pubspec.yaml`.

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
call site — 59 `texture()` and 5 `textureLod()` — passes through the macro
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

## Why the table is pure Dart

Nothing in `webgpu_formats.dart` imports `dart:js_interop` or `package:web`, so
its whole test file runs on the VM in about a second, with no browser and no
GPU. A typo in `"less-equal"` is then a failed unit test rather than a browser
refusing a pipeline at run time on a machine that has a GPU, which is the
worst place to find out.

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
