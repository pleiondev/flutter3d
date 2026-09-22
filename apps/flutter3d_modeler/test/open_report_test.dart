/// The status-line sentence a freshly opened project earns.
///
///     flutter test test/open_report_test.dart
library;

import 'package:flutter3d_modeler/src/open_report.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('countLabel', () {
    test('one of something has no trailing s', () {
      expect(countLabel(1, 'object'), '1 object');
    });

    test('anything else, including zero, does', () {
      expect(countLabel(2, 'object'), '2 objects');
      expect(countLabel(0, 'object'), '0 objects');
    });
  });

  group('describeOpened', () {
    test('names the file, counts each of the three totals, and times the '
        'open', () {
      expect(
        describeOpened(
          name: 'helmet.glb',
          objectCount: 1,
          triangleCount: 14556,
          materialCount: 3,
          openedInMs: 42,
        ),
        'helmet.glb: 1 object, 14556 triangles, 3 materials, opened in 42 ms',
      );
    });

    test('pluralizes down to a single object, triangle and material too', () {
      expect(
        describeOpened(
          name: 'point.glb',
          objectCount: 1,
          triangleCount: 1,
          materialCount: 1,
          openedInMs: 0,
        ),
        'point.glb: 1 object, 1 triangle, 1 material, opened in 0 ms',
      );
    });
  });
}
