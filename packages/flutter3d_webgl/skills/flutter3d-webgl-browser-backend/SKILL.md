---
name: flutter3d-webgl-browser-backend
description: Use when a flutter3d build runs in a browser through WebGL2 — opening the device, the generated shader map, browser tests, and the bugs that only show up here.
---

# WebGL2, and what it is for besides the web

```dart
final device = await openWebGl(width: 1280, height: 720);
```

Most applications call `openDevice` from `flutter3d_backend` and never name this
package: web against native is a conditional export there, and a file importing
both this and `flutter_gpu` compiles for nothing.

This backend is what says whether `flutter3d_hardware` is a real seam or a
description of Impeller. A fake device confirms a call exists; only a second
implementation says it is implementable.
`test/engine_parity_test.dart` draws one scene through both and compares.

## Shaders are generated source, not a bundle

A browser compiles GLSL itself, so the "bundle" is a map from entry point names
to GLSL ES 3.00 source, generated from `flutter3d_shaders`:

    dart run tool/generate_shaders.dart

CI regenerates and diffs it, because the file was once a year out of date and
the browser drew a different sky from Impeller with nothing able to see it. Edit
the GLSL upstream and regenerate; never hand-edit the generated map.

## Running the tests

Five of the six test files are `@TestOn('browser')`:

    flutter test --platform chrome

## Bugs that only appear here

WebGL2 is stricter than Impeller, so this backend finds mistakes the others
tolerate. Each of these was a real scene drawn wrong: a uniform block left
unbound, which WebGL2 refuses, giving an empty frame; an attribute divisor left
set from an earlier draw, so a whole quad read one texture coordinate; a bloom
chain composited upside down, because the framebuffer origin is not Metal's; a
cube shadow atlas addressed by the wrong row. `ARCHITECTURE.md` §13 keeps what
each turned out to be.

When a picture differs between backends, assume a bug in one of them before
assuming rasteriser noise.

## Where it stands against Impeller

All thirty-two golden scenes agree to between 0.01% and 0.6% of pixels differing
by more than 8 per channel — the silhouette's worth two rasterisers always have.
`test/cross_backend_test.dart` holds each scene to its own measured budget, so a
scene that drifts is named instead of absorbed into one tolerance.

The reference set is recorded in a real browser by
`tool/golden_web.sh`, which serves the whole suite from one build — the scene is
a query parameter rather than a compile-time define, which is why recording
takes minutes rather than an hour.
