# flutter3d_samples

The models `flutter3d` is tested against and its demo browses. **Test data, not
a library**: the whole of the Dart here is two path constants.

```dart
import 'package:flutter3d_samples/flutter3d_samples.dart';

// In a widget, through a bundle:
final bytes = await rootBundle.load('$kSamplesAsset/BoxTextured.glb');

// In a test, from disk:
final bytes = File('$kSamplesPath/BoxTextured.glb').readAsBytesSync();
```

## What is in it

| | |
|---|---|
| `Box.glb`, `BoxTextured.glb`, `BoxVertexColors.glb`, `Triangle.gltf`, `cube/` | glTF carried three different ways — a binary chunk, an embedded base64 buffer, an external `.bin` — plus vertex colours and an embedded PNG |
| `BoxAnimated.glb`, `InterpolationTest.glb`, `animated_cube/` | The animation paths: a looping rotation, a parent node moving its child, every interpolation mode |
| `RiggedSimple.glb`, `RiggedFigure.glb`, `simple_skin/` | Skinning, from four joints to a figure |
| `NormalTangentTest.glb`, `NormalTangentMirrorTest.glb` | Tangent handedness, including the mirrored case that catches a sign error |
| `teapot.obj` | An OBJ with no normals and no materials: 1202 vertices, 2256 triangles |
| `f3d/` | The same models converted to `.f3d`, which is what the binary format's tests compare against |

## Why it is its own package

These files were declared in `flutter3d`'s own `flutter.assets`, so every
application that depended on the engine bundled 4.1 MB of test models it never
loads, and the engine's published archive was mostly somebody else's data. They
are still needed — by the decoder tests, which read every path above, and by the
demo, which browses them — so they moved rather than went. A game depends on the
engine and gets no fixtures; a test or a demo depends on this.

## Licence

The **package** is MIT, like the rest of this repository. The **models are
not ours** and keep their own terms, recorded per file with author and source in
[`assets/ATTRIBUTION.md`](assets/ATTRIBUTION.md). Everything shipped here is CC0
or public domain.
