/// Where what a player changed is kept.
///
///     flutter test
///     flutter test --platform chrome test/storage_test.dart
///
/// The second command names this file rather than the package, and that is not
/// fussiness: `@TestOn('vm')` filters what *runs*, not what is compiled, so the
/// two files here that touch `dart:io` would fail the whole browser run before
/// this one got a chance. This is the file with the browser's half in it —
/// `localStorage`, written and read back through the real thing.
///
/// **Two of the four platforms were losing it silently.** The settings and the
/// save were files under `$HOME/Library/Application Support`, which is right on
/// macOS — a sandboxed application's `HOME` *is* its container — and is nowhere
/// on the other three. In a browser `dart:io` throws on the way past
/// `Platform.environment` and the throw was swallowed into defaults, so every
/// launch was a first launch. On Android `HOME` is not the application's
/// anything, so the write failed and was swallowed the same way.
///
/// Neither was visible, and that is the point of this file: a settings document
/// that cannot be written looks exactly like a player who has changed no
/// settings, and a save that cannot be written looks exactly like a player who
/// has not reached a checkpoint.
library;

import 'package:flutter3d_app/flutter3d_app.dart';
import 'package:flutter_test/flutter_test.dart';

// What a settings document does with a storage is a game's, and is tested in
// `flutter3d_game`'s `settings_storage_test.dart`; this file holds the
// storage's own promise.
void main() {
  group('the storage this build actually gets', () {
    test('keeps a document across two of its own instances', () {
      // The real one, whichever it is: `localStorage` under chrome and a file
      // everywhere else. What is checked is the promise both make.
      final storage = defaultStorage('flutter3d_app_test');
      addTearDown(() => storage.remove('probe.json'));

      expect(storage.write('probe.json', '{"kept":true}'), isTrue);

      expect(
        defaultStorage('flutter3d_app_test').read('probe.json'),
        '{"kept":true}',
      );
    });

    test('and forgets one when asked', () {
      final storage = defaultStorage('flutter3d_app_test');
      storage.write('probe.json', 'x');

      storage.remove('probe.json');

      expect(storage.read('probe.json'), isNull);
    });

    test('and reading what was never written is null, not a throw', () {
      expect(defaultStorage('flutter3d_app_test').read('absent.json'), isNull);
    });
  });
}
