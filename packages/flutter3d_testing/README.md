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

`flutter3d_cpu` is a full backend: a software rasteriser that passes the same
conformance suite as Impeller and WebGL. A frame can therefore be drawn with no
driver, no display and no graphics hardware, and a continuous integration
runner can answer "does it still look right".

Every other 3D engine on this platform needs a real device for that check. In
practice that means either a machine nobody wants to pay for or a check nobody
runs.

## Why it is its own package

`flutter3d_cpu` must not depend on `flutter3d`. A backend that could not compile
without the engine would be part of the engine, not an implementation of an
interface. And `flutter3d` must not depend on any backend; a scan in
`tool/structure.dart` enforces that.

So neither of them can hold code that needs both, and this package needs both.

## What a match means

`tolerance` is the share of pixels allowed to differ, and it is zero by
default. What counts as a differing pixel is a separate setting, and its
default is not byte for byte. A pixel differs when red, green or blue is more
than `channel` steps off (8 unless you say otherwise), and alpha is not compared
unless you pass `alpha: true`. This README used to say the tolerance was zero
and stop there, which anyone keeping byte-exact references read as "exact". It
was not exact, and a reference that moved by eight steps everywhere still
passed.

For an exact comparison:

```dart
await expectMatchesGolden(frame, path, channel: 0, alpha: true);
```

The frame comes from a software rasteriser, so the same scene drawn twice is the
same bytes twice. There is no driver, clock or thread to disagree, which means
any difference is a change and not noise. Raise `tolerance` only when something
has been measured to move, and say why in the call.

## What it does not do

It does not compare a software frame against a GPU one. This repository keeps
two separate golden sets on purpose: the same scene differs by a fraction of a
percent between a rasteriser and a driver, and one shared set would need a
tolerance. See the note at the top of
`packages/flutter3d_cpu/test/cross_backend_test.dart`.

References a game records here show what the software backend draws. That is
still the right thing to regress against, because a change that alters the
picture alters it on both.

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
