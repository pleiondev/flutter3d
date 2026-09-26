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

## The contract

What a backend must actually *do* is defined by `flutter3d_conformance`, a
suite each backend runs against itself. An interface can only say that a call
exists. The conformance suite checks that a clear covers the whole attachment
and that uploaded pixels keep their row order.

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
