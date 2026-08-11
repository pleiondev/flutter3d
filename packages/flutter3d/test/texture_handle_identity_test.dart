/// The engine builds no textures at all.
///
/// It used to build them through a top-level function that reached a global
/// graphics context, and the rule then was "only one factory constructs a
/// `TextureHandle`". Textures come from a `GraphicsDevice` now, so the rule
/// here got simpler and stronger: this package constructs **none**. It asks.
///
/// That is what makes a fake device able to stand in for a real one — every
/// texture the engine uses came from something it was handed — and it is the
/// reason `test/node_encoding_test.dart` can assert what a node drew with no
/// GPU in the room.
///
/// The other half of the rule lives in
/// `flutter3d_gpu/test/texture_handle_identity_test.dart`: in the backend,
/// exactly one file may construct one, because one texture must never acquire
/// two handles.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('nothing in lib/ constructs a TextureHandle', () {
    final dir = Directory('lib');
    expect(
      dir.existsSync(),
      isTrue,
      reason: 'run from the package root, where lib/ is',
    );

    final offenders = <String>[];
    var scanned = 0;

    for (final file in dir
        .listSync(recursive: true)
        .whereType<File>()
        .where((File f) => f.path.endsWith('.dart'))) {
      scanned++;
      final path = file.path.replaceAll(r'\', '/');
      final lines = file.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i];
        if (!line.contains('TextureHandle(')) continue;
        if (line.trimLeft().startsWith('///')) continue;
        offenders.add('$path:${i + 1}: ${line.trim()}');
      }
    }

    expect(
      offenders,
      isEmpty,
      reason: 'the engine asks a GraphicsDevice for textures rather than '
          'making them, which is what lets a fake device stand in for a real '
          'one. These build their own:\n${offenders.join('\n')}',
    );
    expect(
      scanned,
      greaterThan(0),
      reason: 'a scan that finds no files proves nothing',
    );
  });
}
