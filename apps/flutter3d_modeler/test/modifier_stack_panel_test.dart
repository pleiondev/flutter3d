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
import 'package:vector_math/vector_math.dart' as vm show Matrix4, Vector3;

ModifierSlot _mirror({bool enabled = true}) => ModifierSlot(
  modifier: MirrorModifier(normal: vm.Vector3(1, 0, 0)),
  enabled: enabled,
);

ModifierSlot _array({int count = 2, bool enabled = true}) => ModifierSlot(
  modifier: ArrayModifier(count: count, offset: vm.Vector3(1, 0, 0)),
  enabled: enabled,
);

Future<void> _pump(
  WidgetTester tester, {
  required List<ModifierSlot> slots,
  ValueChanged<int>? onToggle,
  void Function(int from, int to)? onReorder,
  ValueChanged<Modifier>? onAdd,
  void Function(int index, String field, Object? value)? onSetField,
  ValueChanged<int>? onToggleExport,
  int? operandId,
  int? trianglesIn,
  int? trianglesOut,
}) => tester.pumpWidget(
  MaterialApp(
    theme: modelerTheme(),
    home: Scaffold(
      body: ModifierStackPanel(
        slots: slots,
        onToggle: onToggle ?? (_) {},
        onReorder: onReorder ?? (_, _) {},
        onAdd: onAdd ?? (_) {},
        onSetField: onSetField,
        onToggleExport: onToggleExport,
        operandId: operandId,
        trianglesIn: trianglesIn,
        trianglesOut: trianglesOut,
      ),
    ),
  ),
);

void main() {
  testWidgets('an empty stack says so, and draws no row', (tester) async {
    await _pump(tester, slots: const <ModifierSlot>[]);

    expect(find.text('No modifiers'), findsOneWidget);
    expect(find.byTooltip('Do not show it in the viewport'), findsNothing);
  });

  testWidgets('one modifier shows its own kind and enabled state', (
    tester,
  ) async {
    await _pump(tester, slots: <ModifierSlot>[_mirror()]);

    expect(find.text('Mirror'), findsOneWidget);
    // Mutation: read `enabled` off the wrong slot, or hard-code `true`. Two
    // rows with different states would look identical either way — the
    // tooltip is what says which way the button would go.
    expect(find.byTooltip('Do not show it in the viewport'), findsOneWidget);
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

    // The second row is the disabled one, so it is the one offering to show.
    await tester.tap(find.byTooltip('Show it in the viewport'));
    await tester.pump();

    // Mutation: report index 0 regardless of which button was tapped. The
    // second row's own toggle would silently flip the first modifier.
    expect(toggled, <int>[1]);
  });

  group('ux-13: the second switch, and what the stack costs', () {
    testWidgets('the export switch is its own, and names its own index', (
      tester,
    ) async {
      final toggled = <int>[];
      await _pump(
        tester,
        slots: <ModifierSlot>[
          _mirror(),
          ModifierSlot(
            modifier: MirrorModifier(normal: vm.Vector3(0, 1, 0)),
            inExport: false,
          ),
        ],
        onToggleExport: toggled.add,
      );

      // Mutation: one switch for both. A subdivision a person keeps off
      // while they work is then off in the file as well, and a cage a
      // boolean cuts with cannot be both drawn and left out.
      expect(find.byTooltip('Leave it out of the export'), findsOneWidget);
      await tester.tap(find.byTooltip('Put it in the export'));
      await tester.pump();
      expect(toggled, <int>[1]);
    });

    testWidgets('and no export switch at all where nothing can run one', (
      tester,
    ) async {
      await _pump(tester, slots: <ModifierSlot>[_mirror()]);

      expect(find.byTooltip('Leave it out of the export'), findsNothing);
    });

    testWidgets('the counter says what the stack turns the mesh into', (
      tester,
    ) async {
      await _pump(
        tester,
        slots: <ModifierSlot>[_mirror()],
        trianglesIn: 12,
        trianglesOut: 24,
      );

      // Mutation: show the base count alone, which is what the panel said —
      // nothing. A subdivision at four levels is a thousandfold and the one
      // place to find that out was the status line, after the fact.
      expect(find.text('12 → 24 triangles'), findsOneWidget);
    });

    testWidgets('and says nothing where there is nothing to say', (
      tester,
    ) async {
      await _pump(tester, slots: <ModifierSlot>[_mirror()]);
      expect(find.textContaining('triangles'), findsNothing);
    });
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
    // ignore: deprecated_member_use
    expect(list.onReorder, isNull);
    list.onReorderItem!(0, 1);

    expect(reordered, <(int, int)>[(0, 1)]);
  });

  testWidgets('the Add menu is always present, and offers every kind', (
    tester,
  ) async {
    final added = <Modifier>[];
    await _pump(tester, slots: const <ModifierSlot>[], onAdd: added.add);

    // Mutation: only show "Add" when `slots` is non-empty. A stack starts
    // empty, so an "Add" that only appears once something is already there
    // would be a dead end for the very first modifier.
    expect(find.text('Add'), findsOneWidget);

    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();

    // `ux-13`: a menu, not a link that silently added a mirror on X. Four
    // kinds without a second object to cut with, five with one.
    for (final String kind in <String>[
      'Mirror',
      'Array',
      'Smooth',
      'Subdivision',
    ]) {
      expect(find.text(kind), findsOneWidget, reason: kind);
    }
    expect(find.text('Boolean'), findsNothing);

    await tester.tap(find.text('Subdivision'));
    await tester.pumpAndSettle();
    expect(added.single, isA<SubdivisionModifier>());
  });

  testWidgets('and offers Boolean once there is something to cut with', (
    tester,
  ) async {
    await _pump(tester, slots: const <ModifierSlot>[], operandId: 7);

    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();

    // Mutation: offer it always. A boolean needs an operand and there is no
    // sensible default one, so the entry would be a menu item that refuses.
    expect(find.text('Boolean'), findsOneWidget);
  });

  testWidgets('the Add menu still shows beside an existing stack', (
    tester,
  ) async {
    await _pump(tester, slots: <ModifierSlot>[_mirror()]);

    expect(find.text('Add'), findsOneWidget);
  });

  group('the fields, from the hints', () {
    testWidgets('draws none at all when onSetField is not given', (
      tester,
    ) async {
      await _pump(tester, slots: <ModifierSlot>[_array()]);

      expect(find.byType(TextField), findsNothing);
    });

    testWidgets('a mirror draws its own four, not an array\'s count', (
      tester,
    ) async {
      await _pump(
        tester,
        slots: <ModifierSlot>[_mirror()],
        onSetField: (_, _, _) {},
      );

      // `ux-13`. Mutation: draw `count` and nothing else, which is what
      // `mat-20` left. A mirror's normal, its merge distance, its bisect and
      // its flipped UVs were in the document, editable over MCP, and
      // unreachable from the panel that shows the stack.
      expect(find.text('Merge distance'), findsOneWidget);
      expect(find.text('Normal'), findsOneWidget);
      expect(find.text('Bisect'), findsOneWidget);
      expect(find.text('Flip uv'), findsOneWidget);
      expect(find.text('Count'), findsNothing);
    });

    testWidgets('shows the array\'s own count, and edits it as one '
        'SetModifierField', (tester) async {
      final set = <(int, String, Object?)>[];
      await _pump(
        tester,
        slots: <ModifierSlot>[_array(count: 3)],
        onSetField: (int index, String field, Object? value) =>
            set.add((index, field, value)),
      );

      expect(find.text('3'), findsOneWidget);

      await tester.enterText(
        find.ancestor(of: find.text('3'), matching: find.byType(TextField)),
        '5',
      );
      await tester.testTextInput.receiveAction(TextInputAction.done);

      // mat-20's own acceptance: one edit is one `SetModifierField`, naming
      // the slot's own index and an `int`, the shape `_modifierFieldSet`'s
      // own `'count'` case expects.
      expect(set, <(int, String, Object?)>[(0, 'count', 5)]);
    });

    testWidgets('a boolean\'s operation is a list of what there is', (
      tester,
    ) async {
      final set = <(int, String, Object?)>[];
      await _pump(
        tester,
        slots: <ModifierSlot>[
          ModifierSlot(
            modifier: BooleanModifier(
              operation: CsgOperation.subtract,
              operandId: 7,
              operandTransform: vm.Matrix4.identity(),
            ),
          ),
        ],
        onSetField: (int index, String field, Object? value) =>
            set.add((index, field, value)),
      );

      // Mutation: a text box. An operation is one of three names and a box
      // takes any string, so the command's own refusal becomes the control's
      // only validation.
      expect(find.byType(DropdownButton<String>), findsOneWidget);
      await tester.tap(find.byType(DropdownButton<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('union').last);
      await tester.pumpAndSettle();

      expect(set, <(int, String, Object?)>[(0, 'operation', 'union')]);
    });
  });
}
