# flutter3d_webgpu

`flutter3d_hardware` over WebGPU. The fourth backend, and the one being built.

**Nothing here implements `GraphicsDevice` yet.** What this package holds today
is the two halves a device is built out of. The translation table: every
enumeration the contract names, written as the WebGPU string the specification
spells it with, and the key a device will look each draw's real pipeline up by.
And the bindings: WebGPU's interfaces and dictionaries as `dart:js_interop`
declarations, because `package:web` carries the flag constants and not one
interface. The device, the encoder and the shaders arrive in the waves that
follow, and this package exists ahead of them so that three branches writing
into it do not each invent a `pubspec.yaml`.

The table came from `tool/webgpu_spike`, which drew a triangle through the
contract in a real browser to settle the two answers a table cannot settle on
its own — that a clip-space counter-clockwise winding is WebGPU's `"ccw"`
despite a framebuffer whose y runs down, and that the contract needs no
correction anywhere else. It is moved here unchanged, prose included, so that
what this package asserts is exactly what was measured rather than a retyping
of it.

## Why the bindings are three hundred lines of dictionaries

Every descriptor is an object-literal constructor rather than a map, so a
misspelt member is a compile error. That is worth the typing because the failure
it prevents has no other detector: a browser handed `frontface` where it wanted
`frontFace` does not complain — it takes the default and draws a picture with
the wrong faces missing. Where WebGPU forbids a combination rather than a
spelling, the choice is a named constructor instead of an optional member: an
absent dictionary key and an explicit `null` are different things here, and
`blend: null` — the obvious translation of "blending off" — is the one spelling
this API refuses.

The parameters a triangle can leave at zero are all present, because each of
them is a silent wrong picture rather than an error: a vertex or index buffer
offset, a first index, a base vertex, a first instance. A backend that packs two
meshes into one allocation and drops the offset draws the other mesh and reports
nothing. `webgpu_interop_test.dart` asks about each of them in Chrome, against a
control draw that comes back the other colour.

Validation in WebGPU is asynchronous, so `createRenderPipeline` returns a
pipeline whether or not the descriptor was legal and the complaint goes to the
browser console where no Dart program will see it. `gpuChecked` is the bracket
that turns one into a thrown `GpuDeviceError`, and it is what the conformance
suite's refusal checks will need to be watching.

## What WebGPU cannot say

Two of the fifteen blend factors come back null. OpenGL, Metal and Vulkan all
split the blend constant into a colour form and an alpha form, and `BlendFactor`
mirrors that split; WebGPU has `"constant"` and `"one-minus-constant"` and
nothing else. So `BlendFactor.blendAlpha` in the colour equation is a term the
hardware interface can ask for and this API cannot form. It is reported as
null rather than translated to something close, and the device will answer
`supportsBlendColor` with false — which the contract already asks a caller to
check.

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
