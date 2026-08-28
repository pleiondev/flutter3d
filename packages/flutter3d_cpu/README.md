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
display can render a whole frame and compare it. And a test can mount a real
game and ask what is on the screen — which is how three bugs that every
simulation test passed were finally caught, all of them in the seam between a
simulation that was right and a picture that was wrong.

**It shares nothing with either hardware backend** — no driver, no shading
language, no command buffer — which is what makes agreeing with them mean
something. `test/cross_backend_test.dart` compares its output against the
Impeller reference set with a per-scene budget.

## Comparing frames

`compareFrames` counts the pixels two frames disagree about, with the same
default threshold `tool/golden.sh` uses, and reports the worst single-channel
step beside the count.

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
[`flutter3d_game_racing`](../flutter3d_game_racing). A new game starts from
[`apps/flutter3d_template_app`](../../apps/flutter3d_template_app).
Documentation: <https://flutter3d.pleion.dev>.
