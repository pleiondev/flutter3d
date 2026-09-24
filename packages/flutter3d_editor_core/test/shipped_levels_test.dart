/// Every generated document in the repository, regenerated in Dart and
/// compared byte for byte with the file that is committed.
///
/// **This is what makes the generators the source.** A level edited by hand
/// past its generator, or a generator changed without its output, fails here
/// rather than the next time somebody runs the regeneration and finds a
/// hundred unrelated lines moved. The same comparison runs in CI through
/// `tool/regenerate_levels.dart` and a `git diff`; this one says which file
/// and which generator.
@TestOn('vm')
library;

import 'dart:io';

import 'package:test/test.dart';

import '../tool/levels/shipped.dart';

void main() {
  final root = repositoryRoot(Directory.current.path);
  final source = CheckoutSource(root);

  group('each shipped generator writes the committed bytes', () {
    for (final MapEntry(key: script, value: generator)
        in shippedGenerators.entries) {
      test(script, () {
        final written = generator(source);
        expect(written, isNotEmpty);
        for (final MapEntry(key: path, value: text) in written.entries) {
          // Mutation: change a coordinate in `dungeon.dart`'s crypt and the
          // crypt's document is named here with its first differing line.
          expect(
            text,
            File('$root/$path').readAsStringSync(),
            reason: '$path is not what $script writes',
          );
        }
      });
    }
  });

  test('every document that names a generator names a registered one', () {
    // Throws, naming the document, on a `generatedBy` that leads nowhere.
    final found = trackedDocuments(root);
    expect(found.keys.toSet(), shippedGenerators.keys.toSet());
  });
}
