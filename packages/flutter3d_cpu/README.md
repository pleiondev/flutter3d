# flutter3d_cpu

`flutter3d_hardware` rasterised in Dart, with no GPU under it.

```dart
final device = CpuDevice(
  width: 240,
  height: 160,
  shaders: CpuShaderLibrary(builtinCpuShaders()),
);
final pixels = await device.readPixels(frame);
```

Two things use it. The golden images are drawn with it, so a machine with no
display can render a whole frame and compare it. A test can also mount a real
game and ask what is on the screen. That is how three bugs were caught that
every simulation test had passed; all three sat in the seam between a
simulation that was right and a picture that was wrong.

It shares no driver, shading language or command buffer with either hardware
backend, so when its output agrees with theirs, the agreement is independent
evidence. `test/cross_backend_test.dart` compares its output against the
Impeller reference set with a per-scene budget.

## Comparing frames

`compareFrames` counts the pixels two frames disagree about, with the same
default threshold `tool/golden.sh` uses, and reports the worst single-channel
step beside the count.

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
