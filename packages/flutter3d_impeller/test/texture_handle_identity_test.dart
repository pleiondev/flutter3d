/// One texture, one handle — enforced structurally, in the package that makes
/// textures.
///
/// `TextureHandle` has no `==` and no `hashCode` on purpose: the render target
/// pool lends by identity and the frame's resources release by identity, so
/// `identical()` is the contract. That only holds if one underlying texture
/// never acquires two handles, and nothing in the type system says so. What
/// says so is that a single factory creates the texture and its handle in one
/// expression, and the backend texture never escapes as a value for somebody to
/// wrap a second time.
///
/// This scan is the check. It was proven by adding a second construction site
/// and watching it fail.
///
/// Its other half is in `flutter3d`, which must construct **none** at all: the
/// engine asks a device for textures and never makes one.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The one file allowed to call the constructor.
const Set<String> _allowed = <String>{'lib/src/gpu_texture.dart'};

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

    for (final file
        in dir
            .listSync(recursive: true)
            .whereType<File>()
            .where((File f) => f.path.endsWith('.dart'))) {
      // Relative and with forward slashes, so the expectation reads the way an
      // import does.
      final path = file.path.replaceAll(r'\', '/');
      final lines = file.readAsLinesSync();

      for (var i = 0; i < lines.length; i++) {
        final line = lines[i];
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
      reason:
          'a texture may have exactly one handle, and the way that is made '
          'true is that only gpu_texture.dart constructs one — see the note on '
          'TextureHandle. These build their own:\n${offenders.join('\n')}',
    );
    expect(
      seenInFactory,
      isTrue,
      reason:
          'the factory was renamed or moved; a scan that finds nothing '
          'proves nothing, and this rule moves with it',
    );
  });
}
