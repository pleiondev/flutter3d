/// One texture, one handle — enforced by there being one place that makes them.
///
/// [TextureHandle] carries `identical()` as its contract: the pool records what
/// it has lent out by identity, and `FrameResources` decides what goes back by
/// identity, because a pass that writes the resource it read produces a second
/// version standing on the same texture. Both readings are wrong the moment two
/// handles exist over one backend texture.
///
/// Nothing in the type system says so. What says so is that `createGpuTexture`
/// creates the texture and its handle in the same expression and returns only
/// the handle, so no call site in `lib/` ever holds a bare `gpu.Texture` it
/// could wrap a second time. That is a property of the code rather than of the
/// language, which is exactly the kind that decays quietly — a second
/// `TextureHandle(backend: someTexture, ...)` compiles, runs, renders correctly
/// for a while, and then returns one texture to the pool twice.
///
/// A scan in the manner of `graphics_is_backend_free_test.dart`, and for the
/// same reason: the rule is textual, the set of files is small, and a scan says
/// which file broke it.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The two files allowed to name the constructor: where it is declared, and the
/// one factory that calls it.
const Set<String> _allowed = <String>{
  'lib/src/engine/graphics/texture.dart',
  'lib/src/engine/gpu/gpu_texture.dart',
};

void main() {
  test('nothing in lib/ builds a TextureHandle but the one factory', () {
    final dir = Directory('lib');
    expect(
      dir.existsSync(),
      isTrue,
      reason: 'run from the package root, where lib/ is',
    );

    final offenders = <String>[];
    var seenInFactory = false;

    for (final file in dir
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))) {
      // Relative and with forward slashes, so the expectation reads the way an
      // import does.
      final path = file.path.replaceAll(r'\', '/');
      final lines = file.readAsLinesSync();

      for (var i = 0; i < lines.length; i++) {
        final line = lines[i];
        // The declaration and the `toString` in texture.dart both contain the
        // word; only a call is interesting, and a call is followed by an open
        // paren with no `class`/`String` in front of it.
        if (!line.contains('TextureHandle(')) continue;
        if (line.trimLeft().startsWith('///')) continue;
        if (_allowed.contains(path)) {
          seenInFactory = true;
          continue;
        }
        offenders.add('$path:${i + 1}: ${line.trim()}');
      }
    }

    expect(
      offenders,
      isEmpty,
      reason: 'a texture may have exactly one handle, and the way that is made '
          'true is that only gpu_texture.dart constructs one — see the note on '
          'TextureHandle. These build their own:\n${offenders.join('\n')}',
    );
    expect(
      seenInFactory,
      isTrue,
      reason: 'the factory was renamed or moved; a scan that finds nothing '
          'proves nothing, and this rule moves with it',
    );
  });
}
