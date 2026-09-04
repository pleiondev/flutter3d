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
///
/// **The last group is the half that touches a device.** `bindMaterial` and
/// `loadMaterial` are exported from `flutter3d.dart` and had no caller
/// anywhere — no app, no sample, no test — so a published path from a file on
/// disk to a `Material` the renderer draws with had never been run once. It
/// runs here, against `FakeBackend` and a hand-built KTX2, which needs no
/// live binding: `uploadEncodedImage` sniffs KTX2 before `dart:ui` sees the
/// bytes.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_hardware/testing.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/build_ktx2.dart';

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

/// A directory holding a `.fmat` and whatever sibling files it names.
///
/// `FileAssetSource.resolveUri` resolves a material's texture paths against
/// the material's own directory, so the two have to be written side by side
/// for the binding half to be exercised at all.
String _materialBeside(
  String fmat, {
  Map<String, List<int>> siblings = const <String, List<int>>{},
}) {
  final dir = Directory.systemTemp.createTempSync('flutter3d_bind_');
  addTearDown(() => dir.deleteSync(recursive: true));
  for (final sibling in siblings.entries) {
    File('${dir.path}/${sibling.key}').writeAsBytesSync(sibling.value);
  }
  final path = '${dir.path}/thing.fmat';
  File(path).writeAsStringSync(fmat);
  return path;
}

/// A whole, valid, four-by-four BC7 KTX2 — enough for a real upload without a
/// Flutter binding, since `uploadEncodedImage` sniffs KTX2 before `dart:ui`
/// ever sees the bytes.
List<int> _texture(int seed) => buildKtx2(
  vkFormat: VkFormat.bc7UNormBlock,
  levels: <List<int>>[List<int>.generate(16, (i) => (seed + i) & 0xFF)],
);

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

  // Everything above stops at the document. `bindMaterial` and `loadMaterial`
  // are exported from `flutter3d.dart` and were called by nothing at all —
  // not an app, not a sample, not a test — so the half of the format that
  // touches a device had never run. These four take the same path an
  // application would.
  group('and the half that reaches a device', () {
    // Mutation: passing `albedo: null` to `Material`'s constructor in
    // `bindMaterial` — the document still reads, and the two expectations
    // that the image reached the device report false.
    test('loads a file into a drawable material', () async {
      final device = FakeBackend();
      final warnings = <String>[];
      final material = await loadMaterial(
        FileAssetSource(
          _materialBeside(
            '{"fmat": 1, "name": "brass", "metallic": 0.8, "roughness": 0.3, '
            '"textures": {"albedo": "brass.ktx2"}}',
            siblings: <String, List<int>>{'brass.ktx2': _texture(1)},
          ),
        ),
        device: device,
        warnings: warnings,
      );

      expect(material.name, 'brass');
      expect(material.metallic, 0.8);
      expect(material.roughness, 0.3);
      expect(material.albedo, isNotNull);
      expect(
        device.uploadedTextures.single.format,
        TextureFormat.bc7RGBAUNormInt,
      );
      expect(warnings, isEmpty);
    });

    // Mutation: make `resolve` rethrow instead of catching — the load fails
    // and this whole test throws rather than reporting a warning.
    test('costs a missing image a warning, not the material', () async {
      final warnings = <String>[];
      final material = await loadMaterial(
        FileAssetSource(
          _materialBeside('{"fmat": 1, "textures": {"normal": "gone.ktx2"}}'),
        ),
        device: FakeBackend(),
        warnings: warnings,
      );

      expect(material.normal, isNull);
      expect(warnings.single, contains('gone.ktx2'));
    });

    // The extension point, end to end: a slot no `SurfaceMaterial` field
    // names becomes a `Material.extraTextures` entry the encoder binds by
    // name. Mutation: dropping the `extraTextures` loop from `bindMaterial`
    // leaves the map empty and this reports false.
    test('binds a slot only the application\'s shader knows', () async {
      final material = await loadMaterial(
        FileAssetSource(
          _materialBeside(
            '{"fmat": 1, "lighting": {"shader": "flow"}, '
            '"textures": {"flow": "flow.ktx2"}}',
            siblings: <String, List<int>>{'flow.ktx2': _texture(2)},
          ),
        ),
        device: FakeBackend(),
      );

      expect(material.lighting.shaderName, 'flow');
      expect(material.extraTextures.keys, <String>['flow']);
    });

    // A `.fmat` may ask an extra slot for a sampler, and `Material` has
    // nowhere to keep one: `extraTextures` is `Map<String, TextureHandle>`
    // and the encoder binds those with the device's default. Said out loud
    // rather than dropped. Mutation: deleting the `sampling` check in
    // `bindMaterial`'s extras loop leaves `warnings` empty and this reports
    // false.
    test(
      'says so when an extra slot asks for a sampler it cannot keep',
      () async {
        final warnings = <String>[];
        await loadMaterial(
          FileAssetSource(
            _materialBeside(
              '{"fmat": 1, "textures": {"flow": '
              '{"path": "flow.ktx2", "wrapS": "clampToEdge"}}}',
              siblings: <String, List<int>>{'flow.ktx2': _texture(3)},
            ),
          ),
          device: FakeBackend(),
          warnings: warnings,
        );

        expect(warnings.single, allOf(contains('flow'), contains('sampler')));
      },
    );
  });
}
