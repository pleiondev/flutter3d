# flutter3d_formats

The formats [flutter3d](https://flutter3d.pleion.dev) reads and writes, with no
Flutter SDK behind them: `ModelDocument` and everything a decoder fills in, the
materials it names, and readers for glTF/GLB, OBJ, the engine's own `.f3d`
container and its `.fmat` material.

**Plain Dart.** `dart test` runs the suite with no binding, and a program that
opens a `.glb` needs no window.

```dart
import 'package:flutter3d_formats/flutter3d_formats.dart';

final document = GltfLoader().load(bytes, resolveUri: (request) async => …);
print(document.surfaces.length);

// Back out again, in the engine's own container.
final f3d = F3dWriter().write(document);
```

## Why it is a separate package

`flutter3d` declares `flutter: sdk`. Every file here named Flutter nowhere, and
that bought nobody anything: a program that depended on the engine to read a
model resolved a Flutter SDK it had no use for, and `dart pub get` in a
container without one failed outright. The tool an agent starts with `dart run`,
a service that checks an uploaded asset, a modeller's document layer and a plain
`dart test` all want a glTF reader and none of them want a widget.

## What stayed in the engine

The line is drawn at the bytes: this package turns bytes into a document, and
`flutter3d` is what fetches them and uploads the result.

- `decodeModelInIsolate` — it spawns the isolate, answers `kIsWeb`, and reads
  the file on the isolate that has a platform channel.
- `BundleAssetSource` and `FileAssetSource` — one names Flutter's asset bundle
  and the other `dart:io`. `AssetSource` itself is here, as the abstraction both
  extend, so a decoder takes a source without either coming with it.
- `gltf_resolvers.dart`, which resolves through an `AssetBundle`.
- Everything that names a `GraphicsDevice`: `ModelAsset`, `ModelPart`, texture
  upload and the KTX2 reader, whose formats are the HAL's.

The boundary is checked rather than described: `a flat Dart package resolves
without the Flutter SDK` in `tool/structure.dart` walks this package's
dependencies — direct and transitive — and fails on the first one that would put
a Flutter SDK back in front of a program that only wants to read a model.

`flutter3d` exports this package whole, so an application that already imports
the engine keeps every name it had.

## Licence

MIT.
