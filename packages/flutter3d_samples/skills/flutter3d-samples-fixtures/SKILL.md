---
name: flutter3d-samples-fixtures
description: Use when a test, demo or tool needs a model to load — the fixture set flutter3d is tested against, reached through two path constants, as a dev dependency.
---

# Test data, not a library

```dart
// In a widget, through the asset bundle:
final bytes = await rootBundle.load('$kSamplesAsset/BoxTextured.glb');

// In a test, from disk:
final bytes = File('$kSamplesPath/BoxTextured.glb').readAsBytesSync();
```

Those two constants are the whole of the Dart here.

| | |
|---|---|
| `Box.glb`, `BoxTextured.glb`, `BoxVertexColors.glb`, `Triangle.gltf`, `cube/` | glTF carried three ways — a binary chunk, an embedded base64 buffer, an external `.bin` — plus vertex colours and an embedded PNG |
| `BoxAnimated.glb`, `InterpolationTest.glb`, `animated_cube/` | a looping rotation, a parent moving its child, every interpolation mode |
| `RiggedSimple.glb`, `RiggedFigure.glb`, `simple_skin/` | skinning, from four joints to a figure |
| `NormalTangentTest.glb`, `NormalTangentMirrorTest.glb` | tangent handedness, including the mirrored case that catches a sign error |
| `teapot.obj` | an OBJ with no normals and no materials: 1202 vertices, 2256 triangles |
| `f3d/` | the same models as `.f3d`, which the binary format's tests compare against |

Pick the file that exercises the thing under test rather than the first that
loads: a decoder change that only sees `Box.glb` has not met an external buffer,
a mirrored UV island or a skin.

**Depend on it as a dev dependency.** These files were once assets of
`flutter3d` itself, so every application bundled 4.1 MB of test models it never
loads. A game depends on the engine and gets no fixtures.

## Licence

The package is MIT. **The models are not ours** and keep their own terms,
recorded per file in `assets/ATTRIBUTION.md`. Everything here is CC0 or public
domain — check that file before adding one.
