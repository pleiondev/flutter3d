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
