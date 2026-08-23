/// This package may not import a graphics backend. Ever.
///
/// That is the entire reason it exists, and a rule nobody can check by looking
/// is a rule that lasts until the first hurried afternoon. One
/// `import 'package:flutter_gpu/gpu.dart'` in here and the vocabulary silently
/// becomes flutter_gpu's again, with the type names unchanged so nothing else
/// looks different.
///
/// The complement is `flutter3d/test/backend_is_contained_test.dart`: the
/// engine may not name a backend either. Between them the two say that the only
/// place a graphics API appears in this stack is inside a backend package.
///
/// Deliberately a file scan rather than a dependency assertion: the set is
/// small, the rule is textual, and a scan says which file broke it.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Files allowed to name Flutter, and why.
///
/// The `flutter_gpu` half of the rule has no exceptions and never will. The
/// Flutter half is narrower than it first looks: it is there to stop Flutter's
/// vocabulary leaking into this one, and `PixelFormat` is the collision it was
/// written for — already handled by naming ours `TextureFormat`.
///
/// Showing a finished frame is different. Every backend has to answer it, so a
/// device that could not would not be a usable device — and the answer cannot
/// be a `ui.Image`, because one backend can only produce one through a round
/// trip that costs more than the frame. What both can produce is a widget. See
/// `GraphicsDevice.present`.
///
/// **`package:flutter/` is banned as well as `dart:ui`, on purpose.** Widgets
/// re-export half of `dart:ui`, so a rule that named only `dart:ui` would let
/// the whole of Flutter in through a technicality — and the exception below
/// would then be documenting a loophole rather than a decision.
const Map<String, String> _mayUseFlutter = <String, String>{
  'graphics_device.dart':
      'GraphicsDevice.present returns a widget showing the finished frame, '
          'which every backend must be able to produce and only Flutter can '
          'name',
  // The rule found this the hour the file arrived, which is the argument for
  // having it: `testing.dart` is a `GraphicsDevice` that draws nothing, so it
  // has to answer `present` like any other — and the answer is a widget. It
  // names Flutter for the same reason `graphics_device.dart` does, and for no
  // other; everything else in it is this package's own vocabulary.
  'testing.dart': 'FakeBackend implements GraphicsDevice.present, which is a '
      'widget by the line above',
};

void main() {
  test('nothing here imports a graphics backend', () {
    final dir = Directory('lib');
    expect(
      dir.existsSync(),
      isTrue,
      reason: 'run from the package root, where lib/ is',
    );

    final files = dir
        .listSync(recursive: true)
        .whereType<File>()
        .where((File f) => f.path.endsWith('.dart'))
        .toList();

    expect(
      files,
      isNotEmpty,
      reason: 'a scan that finds nothing proves nothing',
    );

    for (final file in files) {
      final allowsFlutter =
          _mayUseFlutter.containsKey(file.uri.pathSegments.last);
      for (final line in file.readAsLinesSync()) {
        final trimmed = line.trim();
        if (!trimmed.startsWith('import ') && !trimmed.startsWith('export ')) {
          continue;
        }
        expect(
          trimmed.contains('flutter_gpu'),
          isFalse,
          reason: '${file.path} reaches a backend: $trimmed',
        );
        if (allowsFlutter) continue;
        expect(
          trimmed.contains('dart:ui') || trimmed.contains('package:flutter/'),
          isFalse,
          reason: "${file.path} reaches Flutter: $trimmed — this package's "
              'vocabulary is its own. If this is genuinely something every '
              'backend must answer, name it in _mayUseFlutter with the reason',
        );
      }
    }
  });

  test('nor does it depend on one', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    expect(
      pubspec.contains('flutter_gpu'),
      isFalse,
      reason: 'the HAL must not depend on any backend; backends depend on it',
    );
  });
}
