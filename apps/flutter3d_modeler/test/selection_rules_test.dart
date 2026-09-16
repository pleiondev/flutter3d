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

  group('ux-28: what a click inside a mesh is asking for', () {
    ElementPickIntent asked({
      bool extend = false,
      bool alternate = false,
      bool control = false,
    }) => ElementPickIntent.forModifiers(
      extend: extend,
      alternate: alternate,
      control: control,
    );

    test('nothing held is the element under the pointer', () {
      expect(asked(), ElementPickIntent.replace);
    });

    test('shift is the toggle this file already had', () {
      expect(asked(extend: true), ElementPickIntent.toggle);
    });

    test('alt is the loop, and alt with control is the ring', () {
      // The acceptance this row states, as the arithmetic half of it.
      expect(asked(alternate: true), ElementPickIntent.loop);
      expect(asked(alternate: true, control: true), ElementPickIntent.ring);
    });

    test('and shift cannot turn a walk back into a pick', () {
      // Mutation: test shift first. A hand that still has shift down from the
      // gesture before then gets one edge where it asked for a whole loop,
      // which is the most annoying possible answer: it looks like the loop
      // key silently stopped working.
      expect(asked(extend: true, alternate: true), ElementPickIntent.loop);
      expect(
        asked(extend: true, alternate: true, control: true),
        ElementPickIntent.ring,
      );
    });

    test('control on its own is not a walk — it is the box\'s own subtract', () {
      expect(asked(control: true), ElementPickIntent.replace);
      expect(asked(control: true, extend: true), ElementPickIntent.toggle);
    });

    test('and only the two walks are walks', () {
      expect(ElementPickIntent.loop.isWalk, isTrue);
      expect(ElementPickIntent.ring.isWalk, isTrue);
      expect(ElementPickIntent.replace.isWalk, isFalse);
      expect(ElementPickIntent.toggle.isWalk, isFalse);
    });
  });
}
