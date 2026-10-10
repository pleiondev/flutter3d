/// The envelope's version: what a document says it is, and what is refused
/// — readiness review §2.2.7.
///
///     dart test test/formats_test.dart
library;

import 'package:flutter3d_foundation/flutter3d_foundation.dart';
import 'package:test/test.dart';

const FormatSpec _spec = FormatSpec(id: 'f3d.test', version: 3);

Map<String, Object?> _open(Map<String, Object?> document) =>
    _spec.open(document, refuse: DocumentFormatException.new);

void main() {
  test('a document without a version is the first version', () {
    expect(_spec.versionOf(const <String, Object?>{}), 1);
    expect(_spec.versionOf(const <String, Object?>{'version': 2}), 2);
    expect(() => _open(const <String, Object?>{}), returnsNormally);
  });

  test('version 0 and below are refused, not read as 1', () {
    // Mutation: clamp `versionOf` to 1 again (`said >= 1 ? … : 1`) and drop
    // the refusal in `open` — both documents open as version 1.
    for (final said in <int>[0, -1, -7]) {
      expect(_spec.versionOf(<String, Object?>{'version': said}), said);
      expect(
        () => _open(<String, Object?>{'format': 'f3d.test', 'version': said}),
        throwsA(
          isA<DocumentFormatException>().having(
            (DocumentFormatException e) => e.message,
            'message',
            contains('counts from 1'),
          ),
        ),
      );
    }
  });
}
