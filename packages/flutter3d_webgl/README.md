# flutter3d_webgl

`flutter3d_hardware` over WebGL2, for a build that runs in a browser.

```dart
final device = await openWebGl(width: 1280, height: 720);
final renderer = Renderer.create(device: device);
```

**Its value is not only that it runs on the web.** It is the first thing that
could say whether the graphics interface is a seam or a description of Impeller,
because a fake backend can only confirm that a call exists, never that it is
implementable. `test/engine_parity_test.dart` draws the same scene through this
backend and through the hardware one and compares the two pictures.

## Shaders

There is no compiled bundle here — a browser compiles GLSL itself, so a "bundle"
is a map from the engine's entry point names to source text. It is generated
from `flutter3d_shaders`:

    dart run tool/generate_shaders.dart

CI regenerates it and diffs, because the file it produces was once a year out of
date and the browser was drawing a different sky from Impeller with nothing able
to see it.

## Where it stands against Impeller

All thirty-two golden scenes, between 0.01% and 0.6% of pixels differing by more
than 8 per channel — the silhouette's worth of disagreement two rasterisers
always have. `test/cross_backend_test.dart` holds each scene to its own measured
budget, so a scene that starts drifting is named rather than absorbed into one
tolerance covering everything.

Six scenes were once in whole percents, and every one of them was this backend
drawing something else — an empty frame from a uniform block WebGL2 refuses to
leave unbound, a mesh reading one texture coordinate for a whole quad because an
attribute divisor was left set, a bloom chain composited upside down, a cube
shadow atlas addressed by the wrong row. `ARCHITECTURE.md` §13 keeps what each
turned out to be.

## Running the tests

Five of the six test files are `@TestOn('browser')`:

    flutter test --platform chrome

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
