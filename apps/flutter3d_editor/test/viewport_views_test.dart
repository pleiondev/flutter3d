/// The viewport's debug views and the level's own decals and mirrors —
/// read off the screen's source, which no test mounts without a window.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'V steps the viewport through the debug views, and the frame is told',
    () {
      final main = File('lib/main.dart').readAsStringSync();
      expect(main, contains('key == LogicalKeyboardKey.keyV'));
      // Mutation: the view chosen and not handed to the frame.
      expect(main, contains('debugView: DebugViewSettings(view: _debugView)'));
    },
  );

  test(
    'a level\'s decals and mirrors are drawn in the viewport as in the game',
    () {
      final main = File('lib/main.dart').readAsStringSync();
      expect(main, contains('_decals = loaded.wantsDecals'));
      expect(main, contains('decals: DecalSettings(enabled: _decals)'));
      expect(main, contains('enabled: _mirrors'));
    },
  );
}
