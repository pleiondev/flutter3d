/// What a click in the viewport does to the selection.
///
///     flutter test test/selection_rules_test.dart
library;

import 'package:flutter3d_modeler/src/selection_rules.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('nextSelection', () {
    test('a plain click on an unselected object replaces the selection', () {
      expect(
        nextSelection(
          id: 2,
          isService: false,
          current: <int>[1],
          extend: false,
        ),
        <int>[2],
      );
    });

    test('shift-click on an object not yet selected adds it', () {
      expect(
        nextSelection(id: 2, isService: false, current: <int>[1], extend: true),
        <int>[1, 2],
      );
    });

    test('shift-click on an already-selected object removes just that one '
        '(toggle off)', () {
      expect(
        nextSelection(
          id: 2,
          isService: false,
          current: <int>[1, 2, 3],
          extend: true,
        ),
        <int>[1, 3],
      );
    });

    test('a plain click on empty space clears a non-empty selection', () {
      expect(
        nextSelection(
          id: null,
          isService: false,
          current: <int>[1, 2],
          extend: false,
        ),
        <int>[],
      );
    });

    test('a shift-click on empty space leaves the selection as it was — '
        'which is "no change", not an empty list', () {
      expect(
        nextSelection(
          id: null,
          isService: false,
          current: <int>[1, 2],
          extend: true,
        ),
        isNull,
      );
    });

    test('a click on the viewport\'s own furniture (a gizmo handle) never '
        'changes the selection, even with nothing held', () {
      expect(
        nextSelection(
          id: null,
          isService: true,
          current: <int>[],
          extend: false,
        ),
        isNull,
      );
      expect(
        nextSelection(
          id: null,
          isService: true,
          current: <int>[1],
          extend: true,
        ),
        isNull,
      );
    });

    test('clicking on empty space with nothing already selected is "no '
        'change", not a rebuild spent on the same empty answer', () {
      expect(
        nextSelection(
          id: null,
          isService: false,
          current: <int>[],
          extend: false,
        ),
        isNull,
      );
    });

    test('clicking the one already-selected object with no shift is "no '
        'change"', () {
      expect(
        nextSelection(
          id: 1,
          isService: false,
          current: <int>[1],
          extend: false,
        ),
        isNull,
      );
    });
  });
}
