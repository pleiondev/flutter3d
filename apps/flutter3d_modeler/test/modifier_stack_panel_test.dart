/// `ui-08`'s own modifier stack panel: toggling and reordering.
///
///     flutter test test/modifier_stack_panel_test.dart
library;

import 'package:flutter/material.dart';
import 'package:flutter3d_mesh/flutter3d_mesh.dart';
import 'package:flutter3d_model_core/flutter3d_model_core.dart';
import 'package:flutter3d_modeler/src/ui/modifier_stack_panel.dart';
import 'package:flutter3d_modeler/src/ui/theme.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

ModifierSlot _mirror({bool enabled = true}) => ModifierSlot(
  modifier: MirrorModifier(normal: Vector3(1, 0, 0)),
  enabled: enabled,
);

ModifierSlot _array({int count = 2, bool enabled = true}) => ModifierSlot(
  modifier: ArrayModifier(count: count, offset: Vector3(1, 0, 0)),
  enabled: enabled,
);

Future<void> _pump(
  WidgetTester tester, {
  required List<ModifierSlot> slots,
  ValueChanged<int>? onToggle,
  void Function(int from, int to)? onReorder,
  VoidCallback? onAdd,
  void Function(int index, String field, Object? value)? onSetField,
}) => tester.pumpWidget(
  MaterialApp(
    theme: modelerTheme(),
    home: Scaffold(
      body: ModifierStackPanel(
        slots: slots,
        onToggle: onToggle ?? (_) {},
        onReorder: onReorder ?? (_, __) {},
        onAdd: onAdd ?? () {},
        onSetField: onSetField,
      ),
    ),
  ),
);

void main() {
  testWidgets('an empty stack says so, and draws no switch', (tester) async {
    await _pump(tester, slots: const <ModifierSlot>[]);

    expect(find.text('No modifiers'), findsOneWidget);
    expect(find.byType(Switch), findsNothing);
  });

  testWidgets('one modifier shows its own kind and enabled state', (
    tester,
  ) async {
    await _pump(tester, slots: <ModifierSlot>[_mirror()]);

    expect(find.text('Mirror'), findsOneWidget);
    // Mutation: read `enabled` off the wrong slot, or hard-code `true`. Two
    // rows with different states would look identical either way.
    final Switch switchWidget = tester.widget(find.byType(Switch));
    expect(switchWidget.value, isTrue);
  });

  testWidgets('the toggle names its own index, not always zero', (
    tester,
  ) async {
    final toggled = <int>[];
    await _pump(
      tester,
      slots: <ModifierSlot>[_mirror(), _mirror(enabled: false)],
      onToggle: toggled.add,
    );

    await tester.tap(find.byType(Switch).last);
    await tester.pump();

    // Mutation: report index 0 regardless of which switch was tapped. The
    // second row's own toggle would silently flip the first modifier.
    expect(toggled, <int>[1]);
  });

  testWidgets('the list is wired to report a reorder through onReorder', (
    tester,
  ) async {
    final reordered = <(int, int)>[];
    await _pump(
      tester,
      slots: <ModifierSlot>[_mirror(), _mirror(enabled: false)],
      onReorder: (int from, int to) => reordered.add((from, to)),
    );

    // Driven directly rather than through a simulated drag: what this row's
    // own acceptance rests on is that `ReorderModifier`'s index arrives
    // already adjusted for the item that moved, which is `onReorderItem`'s
    // own documented contract, not arithmetic of this panel's own — a
    // pixel-drag simulation would exercise Flutter's own gesture recognizer
    // far more than it would this panel's one line of wiring.
    final ReorderableListView list = tester.widget(
      find.byType(ReorderableListView),
    );
    // Mutation: wire the deprecated `onReorder` instead. That callback's own
    // index is NOT pre-adjusted, and `ReorderModifier.apply` — which removes
    // at `from` before inserting at `to` — would insert one short.
    expect(list.onReorder, isNull);
    list.onReorderItem!(0, 1);

    expect(reordered, <(int, int)>[(0, 1)]);
  });

  testWidgets('the Add link is always present, and calls onAdd', (
    tester,
  ) async {
    var added = 0;
    await _pump(tester, slots: const <ModifierSlot>[], onAdd: () => added++);

    // Mutation: only show "Add" when `slots` is non-empty. A phase-one stack
    // starts empty, so an "Add" link that only appears once something is
    // already there would be a dead end for the very first modifier.
    final add = find.widgetWithText(TextButton, 'Add');
    expect(add, findsOneWidget);

    await tester.tap(add);
    expect(added, 1);
  });

  testWidgets('the Add link still shows beside an existing stack', (
    tester,
  ) async {
    await _pump(tester, slots: <ModifierSlot>[_mirror()]);

    expect(find.widgetWithText(TextButton, 'Add'), findsOneWidget);
  });

  group('mat-20\'s own field: an array\'s own count', () {
    testWidgets('draws no count field when onSetField is not given', (
      tester,
    ) async {
      await _pump(tester, slots: <ModifierSlot>[_array()]);

      expect(find.byType(TextField), findsNothing);
    });

    testWidgets('draws no count field for a modifier that is not an array', (
      tester,
    ) async {
      final set = <(int, String, Object?)>[];
      await _pump(
        tester,
        slots: <ModifierSlot>[_mirror()],
        onSetField: (int index, String field, Object? value) =>
            set.add((index, field, value)),
      );

      // Mutation: draw the count field regardless of the modifier's own
      // kind. `MirrorModifier` has no `count` for it to name.
      expect(find.byType(TextField), findsNothing);
    });

    testWidgets('shows the array\'s own count, and edits it as one '
        'SetModifierField', (tester) async {
      final set = <(int, String, Object?)>[];
      await _pump(
        tester,
        slots: <ModifierSlot>[_mirror(), _array(count: 3)],
        onSetField: (int index, String field, Object? value) =>
            set.add((index, field, value)),
      );

      expect(find.text('3'), findsOneWidget);

      await tester.enterText(find.byType(TextField), '5');
      await tester.testTextInput.receiveAction(TextInputAction.done);

      // mat-20's own acceptance: one edit is one `SetModifierField`, naming
      // the array's own index (1, not 0 — the mirror ahead of it) and an
      // `int`, the shape `_modifierFieldSet`'s own `'count'` case expects.
      expect(set, <(int, String, Object?)>[(1, 'count', 5)]);
    });
  });
}
