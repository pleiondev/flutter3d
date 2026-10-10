# flutter3d_hardware

The vocabulary `flutter3d` writes a frame in: texture and buffer handles,
formats, render targets, pipelines, a command encoder and a shader library.

The package contains no implementation. Three implementations exist,
`flutter3d_impeller` over `flutter_gpu`, `flutter3d_webgl` over WebGL2 and
`flutter3d_cpu` in plain Dart, and this package is what they have in common.
An engine written against it can be handed a backend as a value, so a software
renderer can draw the same frame a GPU does and a test can check that it did.

## What is deliberately not here

Anything a backend can decide for itself. There is no device enumeration,
swapchain or window: an application opens a backend and hands it over, and the
engine never learns which one it got.

## Choosing a backend

Each engine owns a `DeviceRegistry`. A backend package adds itself to the one
it is handed: `registerGpuBackend(registry)`, `registerWebGlBackend` and
`registerCpuBackend` each call `registry.addBackend(name, open, asFallback:
...)`. Then `registry.open(width:, height:)` opens the first backend that
starts, newest first, then the fallback. What shows a finished frame is added the same way,
`registry.addPresenter<MyDevice>(presenter)`, and found with
`registry.presenterFor(device)`. Every addition is a `Registration` that
takes it out again, so a test's fake backend does not leak into the next
test. `flutter3d_app`'s `platformDevices()` makes a registry with this
platform's backends.

## The contract

What a backend must actually *do* is defined by `flutter3d_conformance`, a
suite each backend runs against itself. An interface can only say that a call
exists. The conformance suite checks that a clear covers the whole attachment
and that uploaded pixels keep their row order.

## Capabilities and stability

**Ask one question.** `device.features.has(DeviceFeature.textureArrays)`,
`device.limits.maxColorAttachments`, `device.textureFormatSupport(format)`.
The features are WebGPU's where WebGPU names one, plus what WebGL2 and the
engine add (render-to-mip-level, wireframe, synchronous readback, multi-draw).
The contract covers what WebGPU and WebGL2 can do between them: compute,
storage buffers and textures, texture arrays, 3D and cube arrays, mapped and
synchronous readback, buffer and texture copies, indirect and multi-draws,
occlusion, timestamp and pipeline-statistics queries, render bundles,
compressed formats and multisample resolve.

**A missing capability is a refusal, never a substitution.** Every call a
feature gates throws `UnsupportedCapability`, naming the feature, the backend
and the reason, before anything reaches a driver. A backend that has not built
something yet says so the same way: Impeller lacks most of the 1.0 surface
until `flutter_gpu` exposes it, and each gap is an explicit refusal with a
`TODO(impeller)` at it. When the backend gains the feature it starts listing
it; nothing here changes. `flutter3d_conformance`'s `capabilityChecks` holds
every backend to its own report in both directions.

The pre-1.0 getters (`supportsCompute`, `supportsWireframe`, `maxAnisotropy`
and the rest) are gone in 1.0.0. `dart run flutter3d_build:migrate` rewrites
each into the `features.has(DeviceFeature.x)` or `limits` question that
replaced it.

**A few capabilities are types rather than features**: `EncodedImageUpload`
on a device, `RenderBundleEncoder` on an encoder, and
`SynchronousBufferReadback`, which the main library does not export, since a
stall belongs in a test and not in a frame: a caller imports it from
`package:flutter3d_hardware/testing.dart`, and a backend mixes it in from
`backend.dart`. Each is asked
with `is`, and where a `DeviceFeature` names the same thing a device lists it
exactly when it is the type.

## Who owns a handle

Every handle a device makes has one owner, the code that asked for it, and a
`dispose` that gives it back once. Disposing twice and using a disposed handle
are mistakes, and a debug build says so: the second `dispose` asserts, and a
backend calls `debugCheckLive` before it binds, draws from, copies or reads a
handle. On Impeller, whose `flutter_gpu` objects have no native dispose, the
memory comes back through the collector once nothing holds the object.
`FakeBackend.liveHandles` lists what a test made and did not give back.

**Stable means the snapshot.** From 1.0 this package follows strict semver,
and every backend depends on it through a caret range. `api/flutter3d_hardware.api`
lists every public symbol and signature, and the repository's structure scan
fails on any difference — the same check every published package has (see
"The API is a snapshot" in the repository's `CONTRIBUTING.md`). A change to
the surface therefore needs a version decision before it can pass:

- removing or changing anything listed is a major version;
- adding a member to a type a backend builds on is a minor version, because
  `GraphicsDevice`, `ComputeEncoder` and `TransferEncoder` are `abstract base
  class`es and `PassEncoder` an `abstract base mixin class`: a backend
  `extends` them, and a new member arrives with a body (a feature-gated one
  throws `UnsupportedCapability`) that a backend overrides once it has the
  feature. Every feature-gated member of the three encoders has that body
  already. A member without a default body would break every backend, so it
  waits for a major;
- adding a `DeviceFeature`, a field with a default to a descriptor, or a new
  top-level type is a minor version.

`package:flutter3d_hardware/backend.dart`, the handle constructors and the
`debugCheckLive` check a backend author needs, is held to the same rule: it
is in the snapshot, a constructor there gains only optional parameters within
a major, and a backend written against 1.0.0 compiles against every 1.x.

Regenerate with `dart run api_snapshot --update flutter3d_hardware` from the
repository's `tool/api` once the decision is recorded in `CHANGELOG.md`. Capabilities that
are coming but not designed in detail yet — ray queries, mesh shaders,
bindless resources, immediate data — are reserved `DeviceFeature`s: named,
reported by no backend, and added as calls without breaking anything.

---

Part of [flutter3d](https://github.com/pleiondev/flutter3d), an independent
implementation of a 3D engine for Flutter. It is not a fork or a binding of
another engine, and it is not affiliated with the Flutter team. It has four
switchable rendering backends: Impeller via Flutter GPU, WebGL2, WebGPU and a
software rasteriser. It loads glTF, OBJ and `.f3d`, and has six lighting models,
shadows, bloom, skinning, animation, BVH culling and picking, plus a
deterministic fixed-step game layer with collision, navigation, positional
audio, and gamepad and touch input. Four example games (shooter, platformer,
racing, strategy) are each built on a genre package:
[`flutter3d_game_shooter`](https://pub.dev/packages/flutter3d_game_shooter),
[`flutter3d_game_platformer`](https://pub.dev/packages/flutter3d_game_platformer),
[`flutter3d_game_racing`](https://pub.dev/packages/flutter3d_game_racing),
[`flutter3d_game_strategy`](https://pub.dev/packages/flutter3d_game_strategy).
A new game starts from the editor's scaffold, which writes one from a template:
<https://flutter3d.pleion.dev/first-project/>. Documentation:
<https://flutter3d.pleion.dev>.
