---
name: flutter3d-cpu-rendering-in-a-test
description: Use when rendering a flutter3d frame with no GPU — in a headless test, in CI, or to compare two backends — with CpuDevice, encodePng and compareFrames.
---

# A whole frame, in Dart, with nothing under it

```dart
final device = CpuDevice(
  width: 240,
  height: 160,
  shaders: CpuShaderLibrary(builtinCpuShaders()),
);
final renderer = Renderer.create(device: device);
…
final pixels = await device.readPixels(frameTexture);   // RGBA bytes
File('shot.png').writeAsBytesSync(encodePng(pixels!, 240, 160));
```

Nothing is compiled and nothing is waited for. A bundle name this device has no
Dart stage for comes back as a refusal naming the bundle and the stage, which is
the only sensible answer: a missing stage is otherwise a picture nobody
questions.

Keep targets small. This rasterises in Dart, so 240×160 is a test and 1920×1080
is a wait.

## Why it is worth having

A test can mount a real game and ask what is on the screen. Three bugs that
every simulation test passed were caught that way, all in the seam between a
simulation that was right and a picture that was wrong. If a feature can be
checked as pixels, check it here — no display, no GPU, no golden runner.

It also gives the golden set a second, independently written implementation.
**It shares nothing with either hardware backend** — no driver, no shading
language, no command buffer — which is what makes agreement evidence rather than
a tautology.

## Comparing two frames

```dart
final diff = compareFrames(a, b);            // channel: 8 by default
diff.differing;      // pixels past the threshold
diff.pixels;         // how many there were, so a share can be taken
diff.worstChannel;   // the largest single-channel step
```

Report `worstChannel` beside the count: a thousand pixels off by one is a
resolve difference, ten pixels off by two hundred is a bug.

Reference sets are per backend — this package keeps its own in `test/goldens` —
because the software rasteriser has no multisampling and cannot reproduce
Impeller's images byte for byte, and a shared set would need a tolerance. The
cross-backend question is an ordinary test over the two committed sets
(`test/cross_backend_test.dart`), with a per-scene budget and no device at all.
That is the one CI runs.
