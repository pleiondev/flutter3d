/// `close_guard`: `ui-24`'s own decision behind a close attempt, without
/// Flutter.
///
///     dart test test/close_guard_test.dart
library;

import 'package:flutter3d_modeler/src/close_guard.dart';
import 'package:test/test.dart';

void main() {
  group('needsConfirmation', () {
    test('a dirty document asks first — the row\'s own worked example', () {
      expect(needsConfirmation(isDirty: true), isTrue);
    });

    test('a clean document goes straight through', () {
      expect(needsConfirmation(isDirty: false), isFalse);
    });
  });

  group('shouldClose', () {
    test('keeping editing never writes and never closes', () async {
      var wrote = false;
      final closed = await shouldClose(
        UnsavedChoice.keepEditing,
        write: () async {
          wrote = true;
          return true;
        },
      );

      expect(closed, isFalse);
      expect(wrote, isFalse);
    });

    test('discarding closes without ever writing', () async {
      var wrote = false;
      final closed = await shouldClose(
        UnsavedChoice.discard,
        write: () async {
          wrote = true;
          return true;
        },
      );

      expect(closed, isTrue);
      expect(wrote, isFalse);
    });

    test('a save that lands closes — the row\'s own worked example', () async {
      final closed = await shouldClose(UnsavedChoice.save, write: () async => true);
      expect(closed, isTrue);
    });

    test('a save that fails to land does not close — the row\'s own worked '
        'example', () async {
      final closed = await shouldClose(UnsavedChoice.save, write: () async => false);
      expect(closed, isFalse);
    });
  });

  group('windowTitleFor', () {
    test('a dirty document gets a leading marker', () {
      expect(windowTitleFor(isDirty: true), '• flutter3d modeller');
    });

    test('a clean document gets the plain title, no marker', () {
      expect(windowTitleFor(isDirty: false), 'flutter3d modeller');
    });
  });
}
