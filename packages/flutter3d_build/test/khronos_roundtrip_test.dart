/// `ap-13`: «конвертированное = исходное» через `document_compare` для
/// набора Khronos — every Khronos-sourced sample this repository ships,
/// round-tripped through the real converter, not a synthetic document.
///
/// **Reads `flutter3d_samples`'s files by a relative sibling path, not by
/// depending on the package.** That package needs the Flutter SDK for its
/// own `flutter.assets:` entry — `flatDartPackages` would refuse it here —
/// so this reaches the same files `kSamplesPath` in that package names for
/// exactly this situation, without importing it. `convert_test.dart`'s own
/// `triangle.obj` fixture note explains the same choice for the same
/// reason.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter3d_build/flutter3d_build.dart';
import 'package:flutter3d_formats/flutter3d_formats.dart';
import 'package:test/test.dart';

/// Where `flutter3d_samples` keeps its files, relative to this package's own
/// directory — the same path that package's own `kSamplesPath` documents,
/// spelled out rather than imported.
const String _samples = '../flutter3d_samples/assets';

/// Every file `flutter3d_samples/assets/ATTRIBUTION.md` credits to
/// `KhronosGroup/glTF-Sample-Assets` directly — not `RobotExpressive.glb`
/// (Quaternius/three.js) or the teapot (a different source and not glTF at
/// all), because the plan's own row asks for "the Khronos set" by name.
const List<String> _khronosSamples = <String>[
  'Box.glb',
  'BoxTextured.glb',
  'BoxVertexColors.glb',
  'Triangle.gltf',
  'BoxAnimated.glb',
  'InterpolationTest.glb',
  'NormalTangentTest.glb',
  'NormalTangentMirrorTest.glb',
  'RiggedSimple.glb',
  'RiggedFigure.glb',
  'AnimatedMorphCube.glb',
];

/// A model named by a plain path, read with `dart:io` — [convert.dart]'s own
/// private `_PathSource`, rewritten here because that one is not exported:
/// nothing outside this package's own converter needs a source built from
/// nothing but a path, and a second copy is cheaper than exporting a type
/// whose only job is naming a file.
final class _PathSource extends AssetSource {
  const _PathSource(this.path);

  final String path;

  @override
  String get key => 'file:$path';

  @override
  Future<Uint8List> read() => File(path).readAsBytes();

  @override
  AssetUriResolver get resolveUri => fileUriResolverFor(path);
}

void main() {
  late Directory scratch;

  setUp(() => scratch = Directory.systemTemp.createTempSync('f3d_khronos_'));
  tearDown(() => scratch.deleteSync(recursive: true));

  for (final name in _khronosSamples) {
    test('$name converts to .f3d without losing anything document_compare '
        'checks', () async {
      final sourcePath = '$_samples/$name';
      expect(
        File(sourcePath).existsSync(),
        isTrue,
        reason:
            '$sourcePath is not there — run from packages/flutter3d_build, '
            'where flutter3d_samples is a sibling',
      );

      final outputPath = '${scratch.path}/${name.split('.').first}.f3d';
      final ok = await convertOne(sourcePath, outputPath, stdout, stderr);
      expect(ok, isTrue, reason: '$name refused to convert');

      final source = await decodeModel(
        ModelLoadRequest(source: _PathSource(sourcePath)),
      );
      final readBack = await decodeModel(
        ModelLoadRequest(source: _PathSource(outputPath)),
      );

      final differences = compareModelDocuments(source, readBack);
      expect(
        differences,
        isEmpty,
        reason: differences.join('\n'),
      );
    });
  }
}
