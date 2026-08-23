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

## Running the tests

Five of the six test files are `@TestOn('browser')`:

    flutter test --platform chrome
