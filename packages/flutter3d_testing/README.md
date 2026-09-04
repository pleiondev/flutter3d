# flutter3d_testing

Pixel regression tests for a game, on a machine with no GPU.

```dart
import 'package:flutter3d_testing/flutter3d_testing.dart';

test('the crypt still looks like the crypt', () async {
  final frame = await renderFrame(
    width: 320,
    height: 180,
    build: (device) {
      final scene = Scene();
      // ... put the level in it, uploading meshes to `device`
      return (scene: scene, camera: camera);
    },
  );
  await expectMatchesGolden(frame, 'test/goldens/crypt.png');
});
```

The first run records the reference and says so. Later runs fail when the
picture changes, and the message says by how much and how to re-record.

## Why this can exist here and nowhere else

`flutter3d_cpu` is a full backend — a software rasteriser that passes the same
conformance suite as Impeller and WebGL. So a frame can be drawn with no driver,
no display and no graphics hardware, which is what turns "does it still look
right" into something a continuous integration runner can answer.

Every other 3D engine on this platform needs a real device for that. What
follows is either a machine nobody wants to pay for or a check nobody runs.

## Why it is its own package

`flutter3d_cpu` must not depend on `flutter3d`: a backend that could not compile
without the engine would not be an implementation of an interface, it would be
part of the engine. And `flutter3d` must not depend on a backend at all — a scan
in `tool/structure.dart` holds it to that.

So neither of them can hold something that needs both, and this needs both.

## The tolerance is zero, deliberately

The frame comes from a software rasteriser. The same scene drawn twice is the
same bytes twice: there is no driver, no clock and no thread to disagree. A
difference is therefore a change, not noise.

A test that allows a few pixels of drift is a test that has stopped watching the
drift. Raise `tolerance` only when something is measured to move, and say in the
call why.

## What it does not do

It does not compare a software frame against a GPU one. This repository keeps
two separate golden sets on purpose: the same scene differs by a fraction of a
percent between a rasteriser and a driver, and one shared set would need a
tolerance — see the note at the top of
`packages/flutter3d_cpu/test/cross_backend_test.dart`.

A game's references made here say what the software backend draws. That is still
the right thing to regress against: a change that alters the picture alters it on
both.

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
