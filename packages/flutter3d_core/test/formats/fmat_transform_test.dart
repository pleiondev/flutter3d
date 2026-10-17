/// A `.fmat` texture slot keeps its `KHR_texture_transform` — the tiling a
/// converter reads out of a Godot or Unity material.
///
/// An additive key on the slot object, `transform`, so a version 1 reader
/// that does not know it reads the slot as it always did (the rule at the
/// top of `fmat.dart`); no version bump.
///
///     dart test test/formats/fmat_transform_test.dart
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter3d_core/formats.dart';
import 'package:test/test.dart';

Uint8List _bytes(String text) => Uint8List.fromList(utf8.encode(text));

const String _tiled = '''
{
  "fmat": 1,
  "baseColor": [1, 1, 1, 1],
  "textures": {
    "albedo": {
      "path": "brick.png",
      "transform": {"offset": [0.25, 0.5], "scale": [4, 2], "rotation": 0.5}
    },
    "normal": "brick_n.png"
  }
}
''';

void main() {
  test('a slot\'s transform is read and written back', () {
    // Mutation: leave `transform` out of `binding` in `readFmat` — the
    // albedo comes back with no transform, and the tiling a converter wrote
    // is lost on the first read.
    // Mutation: leave it out of `slot` in `writeFmat` — the second read
    // finds a plain path.
    final first = readFmat(_bytes(_tiled), name: 'brick');
    final transform = first.surface.baseColorTexture!.transform!;
    expect(transform.offset.x, 0.25);
    expect(transform.offset.y, 0.5);
    expect(transform.scale.x, 4.0);
    expect(transform.scale.y, 2.0);
    expect(transform.rotation, 0.5);
    expect(first.surface.normalTexture!.transform, isNull);

    final again = readFmat(_bytes(writeFmat(first)), name: 'brick');
    final back = again.surface.baseColorTexture!.transform!;
    expect(back.sameAs(transform), isTrue);
    expect(again.surface.normalTexture!.transform, isNull);
  });

  test('only what moves is written, and a slot with nothing else stays an '
      'object', () {
    final document = readFmat(
      _bytes('''
{
  "fmat": 1,
  "textures": {"albedo": {"path": "a.png", "transform": {"scale": [3, 3]}}}
}
'''),
    );
    final written =
        (json.decode(writeFmat(document)) as Map<String, Object?>)['textures']!
            as Map<String, Object?>;
    expect(written['albedo'], <String, Object?>{
      'path': 'a.png',
      'transform': <String, Object?>{
        'scale': <double>[3.0, 3.0],
      },
    });
  });

  test('a transform that moves nothing is a plain path', () {
    final document = readFmat(
      _bytes('''
{"fmat": 1, "textures": {"albedo": {"path": "a.png", "transform": {}}}}
'''),
    );
    final written =
        (json.decode(writeFmat(document)) as Map<String, Object?>)['textures']!
            as Map<String, Object?>;
    expect(written['albedo'], 'a.png');
  });
}
