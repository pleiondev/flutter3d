/// Where a document too large for [Storage] lives.
///
///     flutter test test/binary_storage_test.dart
///     flutter test --platform chrome test/binary_storage_test.dart
///
/// The second command is the one that matters for `IndexedDbBinaryStorage` —
/// the same reasoning `storage_test.dart` gives for its own two commands.
/// Nothing here is exercised by the VM run alone; static analysis of the web
/// file checks that the JS interop *types* line up, not that a real browser's
/// IndexedDB actually round-trips a value through it.
library;

import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter3d_app/flutter3d_app.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('the binary storage this build actually gets', () {
    test('keeps bytes across two of its own instances', () async {
      final storage = defaultBinaryStorage('flutter3d_app_test');
      addTearDown(() => storage.remove('probe.bin'));

      final bytes = Uint8List.fromList(<int>[
        0,
        1,
        2,
        255,
        254,
        253,
        for (var i = 0; i < 300; i++) i % 256,
      ]);
      await storage.write('probe.bin', bytes);

      final readBack = await defaultBinaryStorage(
        'flutter3d_app_test',
      ).read('probe.bin');
      // Mutation: store a `Blob`/base64 detour and unwrap it wrong, or read
      // back a truncated buffer. Bytes past 255 and a length past one
      // typed-array page both have to survive, not just the easy short case.
      expect(readBack, bytes);
    });

    test('and forgets one when asked', () async {
      final storage = defaultBinaryStorage('flutter3d_app_test');
      await storage.write('probe.bin', Uint8List.fromList(<int>[1, 2, 3]));

      await storage.remove('probe.bin');

      expect(await storage.read('probe.bin'), isNull);
    });

    test('and reading what was never written is null, not a throw', () async {
      expect(
        await defaultBinaryStorage('flutter3d_app_test').read('absent.bin'),
        isNull,
      );
    });

    test('two documents under one storage do not collide', () async {
      final storage = defaultBinaryStorage('flutter3d_app_test');
      addTearDown(() async {
        await storage.remove('a.bin');
        await storage.remove('b.bin');
      });

      await storage.write('a.bin', Uint8List.fromList(<int>[1]));
      await storage.write('b.bin', Uint8List.fromList(<int>[2]));

      expect(await storage.read('a.bin'), Uint8List.fromList(<int>[1]));
      expect(await storage.read('b.bin'), Uint8List.fromList(<int>[2]));
    });

    test('writing again replaces rather than appends', () async {
      final storage = defaultBinaryStorage('flutter3d_app_test');
      addTearDown(() => storage.remove('probe.bin'));

      await storage.write('probe.bin', Uint8List.fromList(<int>[1, 2, 3]));
      await storage.write('probe.bin', Uint8List.fromList(<int>[9]));

      expect(await storage.read('probe.bin'), Uint8List.fromList(<int>[9]));
    });

    // `ux-01`'s own root cause. The modeller's autosave key is
    // `autosave/<hash>` (`recoveryPathFor`), a name with a directory in it
    // that nothing created: the write threw "No such file or directory" on
    // every attempt and answered `false`, for a whole session at a time.
    test('a name with a directory in it writes, and reads back', () async {
      final storage = defaultBinaryStorage('flutter3d_app_test');
      addTearDown(() => storage.remove('nested/deeper/probe.bin'));

      final bytes = Uint8List.fromList(<int>[4, 5, 6]);
      // Mutation: create the storage's own root instead of the file's own
      // parent — the only shape of name that then still works is one with no
      // directory in it, and this write throws.
      await storage.write('nested/deeper/probe.bin', bytes);

      expect(await storage.read('nested/deeper/probe.bin'), bytes);
    });

    // A write the platform refused throws, as `Storage.write` does: it used
    // to answer `false` and say nothing a screen could show.
    test(
      'a refused write throws a StorageException naming the document',
      () async {
        final storage = defaultBinaryStorage('flutter3d_app_test');
        addTearDown(() => storage.remove('blocker.bin'));
        await storage.write('blocker.bin', Uint8List.fromList(<int>[1]));

        // Mutation: catch the failure and return as before, and nothing is
        // thrown for a document whose parent is a file.
        await expectLater(
          storage.write('blocker.bin/inner.bin', Uint8List.fromList(<int>[2])),
          throwsA(
            isA<StorageException>().having(
              (StorageException e) => e.name,
              'name',
              'blocker.bin/inner.bin',
            ),
          ),
        );
      },
      // IndexedDB keys are strings; no name it is given can be refused.
      skip: kIsWeb,
    );
  });
}
