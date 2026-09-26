# flutter3d_webgl

`flutter3d_hardware` over WebGL2, for a build that runs in a browser.

```dart
final device = await openWebGl(width: 1280, height: 720);
final renderer = Renderer.create(device: device);
```

Besides running on the web, this backend was the first thing that could say
whether the graphics interface is a seam or a description of Impeller. A fake
backend can only confirm that a call exists, never that it is implementable.
`test/engine_parity_test.dart` draws the same scene through this backend and
through the hardware one and compares the two pictures.

## Shaders

There is no compiled bundle here. A browser compiles GLSL itself, so a
"bundle" is a map from the engine's entry point names to source text. It is
generated from `flutter3d_shaders`:

    dart run tool/generate_shaders.dart

CI regenerates it and diffs. The generated file was once a year out of date,
and the browser drew a different sky from Impeller without anything noticing.

## Where it stands against Impeller

In all thirty-two golden scenes, between 0.01% and 0.6% of pixels differ from
Impeller by more than 8 per channel. That is the silhouette's worth of
disagreement two rasterisers always have. `test/cross_backend_test.dart` holds
each scene to its own measured budget, so a scene that starts drifting is named
instead of being absorbed into one tolerance covering everything.

Six scenes once differed in whole percents, and every one of them was this
backend drawing something else:

- an empty frame, from a uniform block WebGL2 refuses to leave unbound
- a mesh reading one texture coordinate for a whole quad, because an attribute
  divisor was left set
- a bloom chain composited upside down
- a cube shadow atlas addressed by the wrong row

`ARCHITECTURE.md` §13 records what each one turned out to be.

## Running the tests

Five of the six test files are `@TestOn('browser')`:

    flutter test --platform chrome

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
