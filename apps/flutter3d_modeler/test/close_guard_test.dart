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
      final closed = await shouldClose(
        UnsavedChoice.save,
        write: () async => true,
      );
      expect(closed, isTrue);
    });

    test('a save that fails to land does not close — the row\'s own worked '
        'example', () async {
      final closed = await shouldClose(
        UnsavedChoice.save,
        write: () async => false,
      );
      expect(closed, isFalse);
    });
  });

  group('windowTitleFor', () {
    test('a dirty document gets a leading marker', () {
      expect(
        windowTitleFor(isDirty: true, name: 'teapot'),
        '• teapot — flutter3d modeller',
      );
    });

    test('a clean document gets the plain title, no marker', () {
      expect(
        windowTitleFor(isDirty: false, name: 'teapot'),
        'teapot — flutter3d modeller',
      );
    });

    test("ux-30: the document's own name leads, because that is the fact a "
        'title bar is for', () {
      // Mutation: name the application and nothing else, as this did.
      // Somebody with three windows open — which a browser tab strip makes
      // ordinary — then has three labels that cannot be told apart, and the
      // application's own name is already in the menu bar.
      expect(
        windowTitleFor(isDirty: false, name: 'robot'),
        startsWith('robot'),
      );
    });

    test('and a document with no name of its own still has one', () {
      for (final String nameless in <String>['', '   ']) {
        expect(
          windowTitleFor(isDirty: false, name: nameless),
          'untitled — flutter3d modeller',
        );
      }
      // The default is the same word, so a caller that has nothing to say
      // and a caller that says nothing agree.
      expect(windowTitleFor(isDirty: false), 'untitled — flutter3d modeller');
    });
  });
}
