/// A material format the engine does not ship, read by a reader the
/// application brings.
///
///     flutter test test/material_loader_test.dart
///
/// **The plugin boundary for looks.** Its sibling, `model_decoder_test.dart`,
/// pins the same thing for geometry and spends most of its words on where the
/// list of decoders lives, because a model is decoded on a background isolate
/// and statics do not cross one. **None of that applies here, and this file is
/// where that difference is stated rather than assumed**: a material is a few
/// hundred bytes of text, it is read where it is asked for, and the interface is
/// synchronous because there is nothing to move off the frame.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter_test/flutter_test.dart';

/// A format invented for this test: one line, `TOYMAT <roughness>`.
///
/// Deliberately not a real format. What is being checked is that the engine
/// hands the file over and takes back a material, not that anybody can parse
/// anything.
final class _ToyMaterials implements MaterialDecoder {
  const _ToyMaterials({this.greedy = false});

  /// Whether it also claims `.fmat`, which is how *replacing* the built-in
  /// reader is tested rather than merely extending it.
  final bool greedy;

  @override
  bool handles(String fileName, Uint8List bytes) =>
      greedy || fileName.endsWith('.toymat');

  @override
  MaterialDocument decode(Uint8List bytes, String fileName) =>
      MaterialDocument(surface: SurfaceMaterial(name: 'toy', roughness: 0.125));
}

/// Writes [content] to a file this test owns and removes.
String _fileNamed(String name, String content) {
  final dir = Directory.systemTemp.createTempSync('flutter3d_fmat_');
  addTearDown(() => dir.deleteSync(recursive: true));
  final path = '${dir.path}/$name';
  File(path).writeAsStringSync(content);
  return path;
}

const String _steel = '{"fmat": 1, "name": "steel", "metallic": 1.0}';

void main() {
  test(
    'a format the engine never heard of loads through its own reader',
    () async {
      // The whole premise. Mutation: consult no decoders — the load throws on a
      // suffix it does not know, which is what this used to do for every format
      // that was not one of ours.
      final document = await loadMaterialDocument(
        FileAssetSource(_fileNamed('rusty.toymat', 'TOYMAT 0.125')),
        decoders: const <MaterialDecoder>[_ToyMaterials()],
      );

      expect(document.surface.name, 'toy');
      expect(document.surface.roughness, 0.125);
    },
  );

  test('and a decoder may replace the built-in one, not only extend it', () async {
    // A project with its own opinion about `.fmat` — a variant, a stricter
    // reader, one that resolves paths through its own asset pipeline — gets its
    // own reader. That only works if application decoders are consulted first.
    //
    // Mutation: try the built-in reader before the list — the file reads as
    // `steel` and this fails.
    final document = await loadMaterialDocument(
      FileAssetSource(_fileNamed('steel.fmat', _steel)),
      decoders: const <MaterialDecoder>[_ToyMaterials(greedy: true)],
    );

    expect(document.surface.name, 'toy');
  });

  test('and with no decoder at all the engine reads its own', () async {
    final document = await loadMaterialDocument(
      FileAssetSource(_fileNamed('steel.fmat', _steel)),
    );

    expect(document.surface.name, 'steel');
    expect(document.surface.metallic, 1.0);
  });

  test('and a material with the wrong suffix is still read', () async {
    // Suffixes are a convention and files get renamed; the bytes say what a file
    // is. Mutation: require the suffix — fails here.
    final document = await loadMaterialDocument(
      FileAssetSource(_fileNamed('steel.json', _steel)),
    );

    expect(document.surface.name, 'steel');
  });

  test('and a file nobody claimed says what to do about it', () async {
    // Not a silent empty material: a level that renders untextured grey because
    // one file was in a format nobody reads is a bug report nobody can act on.
    //
    // Mutation: return an empty document instead of throwing — fails here.
    await expectLater(
      loadMaterialDocument(
        FileAssetSource(_fileNamed('rusty.toymat', 'TOYMAT 0.125')),
      ),
      throwsA(
        isA<FormatException>().having(
          (e) => e.message,
          'message',
          allOf(contains('MaterialDecoder'), contains('.fmat')),
        ),
      ),
    );
  });
}
