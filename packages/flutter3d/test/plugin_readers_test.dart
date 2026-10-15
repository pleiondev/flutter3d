/// What the engine's plugins brought reaches the files the engine reads: a
/// `.fmat` drawn with a plugin's lit model reads as that model against the
/// renderer's table, and an image in a plugin's format is decoded by its
/// codec when a material binds it.
///
///     flutter test test/plugin_readers_test.dart
///
/// Mutation: drop `lightingModels:` from `loadMaterialDocument`'s
/// `readFmat`, and the first test refuses the file it should open; drop
/// `codecs:` from `bindMaterial`'s upload, and the second binds no albedo.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_hardware/testing.dart';
import 'package:flutter_test/flutter_test.dart';

/// `PIX!`, a width and a height of a byte each, then grey: an image format
/// of a plugin's own.
final class _Pix extends TextureCodec {
  const _Pix();

  @override
  String get name => 'acme_pix.pix';

  @override
  bool sniff(Uint8List head) =>
      head.length >= 6 && String.fromCharCodes(head.sublist(0, 4)) == 'PIX!';

  @override
  Future<Rgba8Image?> decode(TextureDecodeContext context) async => Rgba8Image(
    width: context.bytes[4],
    height: context.bytes[5],
    pixels: Uint8List(context.bytes[4] * context.bytes[5] * 4)
      ..fillRange(0, context.bytes[4] * context.bytes[5] * 4, 96),
  );
}

/// A directory holding `thing.fmat` and [siblings] beside it.
String _material(
  String fmat, {
  Map<String, List<int>> siblings = const <String, List<int>>{},
}) {
  final dir = Directory.systemTemp.createTempSync('flutter3d_readers_');
  addTearDown(() => dir.deleteSync(recursive: true));
  for (final MapEntry(key: name, value: bytes) in siblings.entries) {
    File('${dir.path}/$name').writeAsBytesSync(bytes);
  }
  final path = '${dir.path}/thing.fmat';
  File(path).writeAsStringSync(fmat);
  return path;
}

void main() {
  test('a material drawn with a plugin\'s model reads against the engine\'s '
      'table, and is refused without it', () async {
    const ink = LightingModel('Ink', 'acme_ink__Ink');
    final renderer = Renderer.create(device: FakeBackend());
    renderer.lightingModels.register(ink);
    final path = _material(
      '{"fmat": 1, "name": "page", "lighting": "acme_ink.Ink"}',
    );

    final read = await loadMaterialDocument(
      FileAssetSource(path),
      lightingModels: renderer.lightingModels,
    );
    expect(read.lighting, same(ink));

    // With no table, the plugin the file needs is named.
    await expectLater(
      loadMaterialDocument(FileAssetSource(path)),
      throwsA(
        isA<FmatFormatException>().having(
          (FmatFormatException e) => e.message,
          'message',
          contains('acme_ink'),
        ),
      ),
    );
  });

  test('an image in a plugin\'s format is decoded by its codec', () async {
    final path = _material(
      '{"fmat": 1, "name": "page", "textures": {"albedo": "page.pix"}}',
      siblings: <String, List<int>>{
        'page.pix': <int>[...'PIX!'.codeUnits, 2, 3],
      },
    );
    final source = FileAssetSource(path);
    final document = await loadMaterialDocument(source);
    final codecs = TextureCodecs()..add(const _Pix());

    final bound = await bindMaterial(
      document,
      device: FakeBackend(),
      resolveUri: source.resolveUri,
      decodeImage: (_) async => null,
      codecs: codecs,
    );
    expect((bound.albedo?.width, bound.albedo?.height), (2, 3));

    final warnings = <String>[];
    final without = await bindMaterial(
      document,
      device: FakeBackend(),
      resolveUri: source.resolveUri,
      decodeImage: (_) async => null,
      warnings: warnings,
    );
    expect(without.albedo, isNull);
    expect(warnings, isNotEmpty);
  });
}
