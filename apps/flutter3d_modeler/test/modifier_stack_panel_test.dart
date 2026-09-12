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

Future<void> _pump(
  WidgetTester tester, {
  required List<ModifierSlot> slots,
  ValueChanged<int>? onToggle,
  void Function(int from, int to)? onReorder,
}) => tester.pumpWidget(
  MaterialApp(
    theme: modelerTheme(),
    home: Scaffold(
      body: ModifierStackPanel(
        slots: slots,
        onToggle: onToggle ?? (_) {},
        onReorder: onReorder ?? (_, __) {},
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
}
