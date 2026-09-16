/// `ux-14`'s own outliner: the tree it draws, what a modified click
/// selects, and what hiding a parent does to the children under it.
///
///     flutter test test/outliner_test.dart
library;

import 'package:flutter/material.dart' hide Material;
import 'package:flutter3d_mesh/flutter3d_mesh.dart';
import 'package:flutter3d_model_core/flutter3d_model_core.dart' hide Outcome;
import 'package:flutter3d_modeler/src/ui/properties/outliner.dart';
import 'package:flutter3d_modeler/src/ui/theme.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart' as vm show Matrix4;

ModelObject _object(int id, {int? parent, bool visible = true}) => ModelObject(
  id: id,
  name: 'o$id',
  geometry: EditedGeometry(EditMesh.cuboid()),
  transform: vm.Matrix4.identity(),
  parent: parent,
  visible: visible,
);

/// root → limb → hand, and a second root beside it.
List<ModelObject> _threeDeep() => <ModelObject>[
  _object(1),
  _object(2, parent: 1),
  _object(3, parent: 2),
  _object(4),
];

void main() {
  group('ux-14: the tree', () {
    test('a three-level hierarchy comes back indented, parents first', () {
      final List<OutlinerRow> rows = outlinerRows(_threeDeep());

      // The acceptance this row states. Mutation: draw `project.objects` in
      // order, which is what the panel did. A rig is forty bones under a
      // root and reads as one flat column, so the one thing an outliner is
      // for — what is under what — is the one thing it cannot say.
      expect(
        rows.map((OutlinerRow it) => (it.object.id, it.depth)),
        <(int, int)>[(1, 0), (2, 1), (3, 2), (4, 0)],
      );
    });

    test('and an object whose parent is not there hangs at the top', () {
      final List<OutlinerRow> rows = outlinerRows(<ModelObject>[
        _object(1),
        _object(9, parent: 404),
      ]);

      // Mutation: drop it. A document somebody has edited by hand then
      // hides the very object they need to reach to fix it.
      expect(rows.map((OutlinerRow it) => it.object.id), <int>[1, 9]);
      expect(rows.last.depth, 0);
    });

    test('a cycle does not hang the walk', () {
      final List<OutlinerRow> rows = outlinerRows(<ModelObject>[
        _object(1, parent: 2),
        _object(2, parent: 1),
      ]);

      // Neither is reachable from the top, so neither is drawn — and the
      // point is that this answers at all. `SetParent` refuses to build one;
      // a file edited by hand is what this survives.
      expect(rows, isEmpty);
    });
  });

  group('ux-14: what a modified click selects', () {
    final List<OutlinerRow> rows = outlinerRows(_threeDeep());

    List<int> picked(List<int> current, int id, OutlinerPick how, {int? at}) =>
        outlinerSelection(
          current: current,
          rows: rows,
          id: id,
          how: how,
          anchor: at,
        );

    test('a bare click is that one alone', () {
      expect(picked(<int>[1, 2], 4, OutlinerPick.only), <int>[4]);
    });

    test('control adds, and takes away again', () {
      expect(picked(<int>[1], 4, OutlinerPick.toggle), <int>[1, 4]);
      // Mutation: always add. Dropping one row out of a selection of forty
      // is then thirty-nine clicks, which is the complaint the element
      // picker's own shift already answers.
      expect(picked(<int>[1, 4], 4, OutlinerPick.toggle), <int>[1]);
    });

    test('shift takes everything between, in tree order', () {
      // Rows are 1, 2, 3, 4 in tree order — so from 2 to 4 is three of them.
      expect(picked(<int>[], 4, OutlinerPick.through, at: 2), <int>[2, 3, 4]);
    });

    test('and the same range backwards is the same range', () {
      // Mutation: walk from the anchor forwards only. A shift-click above
      // the anchor then selects one row, which is the half of the gesture
      // people use when they overshoot.
      expect(picked(<int>[], 2, OutlinerPick.through, at: 4), <int>[2, 3, 4]);
    });

    test('shift with nothing to reach back to is a plain click', () {
      expect(picked(<int>[], 3, OutlinerPick.through), <int>[3]);
    });
  });

  group('ux-14: hiding, and what it takes with it', () {
    test('hiding a parent hides its children', () {
      final ModelProject project = ModelProject(objects: _threeDeep());
      final ModelHistory history = ModelHistory(project);

      expect(history.run(const SetObjectVisible(id: 1, to: false)), isNull);

      // The acceptance this row states, as the document half of it —
      // `scene_sync_test.dart` has the viewport half. Mutation: answer only
      // the object's own flag. Hiding a rig's root then leaves forty bones
      // on screen, and the toggle has to be pressed forty-one times.
      expect(history.project.isVisible(1), isFalse);
      expect(history.project.isVisible(2), isFalse);
      expect(history.project.isVisible(3), isFalse);
      // The other root is untouched.
      expect(history.project.isVisible(4), isTrue);
      // And the children's own flags are where they were, so unhiding the
      // parent brings back exactly what was visible before.
      expect(history.project[2]!.visible, isTrue);
    });

    test('showing what is already shown is refused rather than a step', () {
      final ModelHistory history = ModelHistory(
        ModelProject(objects: _threeDeep()),
      );

      // Mutation: land it anyway. The undo stack then fills with steps that
      // changed nothing, and Ctrl+Z stops doing what a person expects.
      expect(
        history.run(const SetObjectVisible(id: 1, to: true)),
        contains('already visible'),
      );
      expect(history.canUndo, isFalse);
    });

    test('locking is its own flag, and does not hide', () {
      final ModelHistory history = ModelHistory(
        ModelProject(objects: _threeDeep()),
      );

      expect(history.run(const SetObjectLocked(id: 1, to: true)), isNull);

      expect(history.project[1]!.locked, isTrue);
      // Mutation: treat locked as hidden. The floor a person keeps catching
      // with the pointer is exactly the thing they need to go on seeing.
      expect(history.project.isVisible(1), isTrue);
    });

    test('and both survive the journal', () {
      for (final ModelCommand command in <ModelCommand>[
        const SetObjectVisible(id: 1, to: false),
        const SetObjectLocked(id: 1, to: true),
      ]) {
        final ModelCommand? read = modelCommandFromJson(command.toJson());
        expect(read, isNotNull, reason: command.name);
        expect(read!.arguments, command.arguments, reason: command.name);
      }
    });
  });

  group('ux-14: the panel', () {
    Future<void> pump(
      WidgetTester tester, {
      required List<ModelObject> objects,
      List<int> selected = const <int>[],
      void Function(int id, bool to)? onVisible,
      void Function(int id, String to)? onRename,
      void Function(int id, int? to)? onReparent,
    }) async {
      tester.view
        ..physicalSize = const Size(400, 900)
        ..devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: modelerTheme(),
          home: Scaffold(
            body: Outliner(
              objects: objects,
              selected: selected,
              onPick: (_, _) {},
              onVisible: onVisible ?? (_, _) {},
              onLocked: (_, _) {},
              onRename: onRename ?? (_, _) {},
              onReparent: onReparent ?? (_, _) {},
            ),
          ),
        ),
      );
    }

    testWidgets('a child is drawn further in than its parent', (
      WidgetTester tester,
    ) async {
      await pump(tester, objects: _threeDeep());

      final double root = tester.getTopLeft(find.text('o1')).dx;
      final double limb = tester.getTopLeft(find.text('o2')).dx;
      final double hand = tester.getTopLeft(find.text('o3')).dx;

      expect(limb, greaterThan(root));
      expect(hand, greaterThan(limb));
    });

    testWidgets('and forty objects do not make a forty-row panel', (
      WidgetTester tester,
    ) async {
      await pump(
        tester,
        objects: <ModelObject>[for (var i = 1; i <= 40; i++) _object(i)],
      );
      final double row = rowHeightOf(tester.element(find.byType(Outliner)));

      // Ten rows and no more, whatever the project holds. **Mutation: a
      // `Column` of every object**, which is what this drew. Forty of them
      // is thirteen hundred pixels of panel in front of Transform, Material
      // and the modifier stack — and the thirty past the fold are laid out
      // and clipped, which is the subtree `_RenderObjectSemantics` walked
      // into with no geometry computed for it.
      expect(tester.getSize(find.byType(Outliner)).height, 10 * row);

      // A list that fits is still drawn whole: four objects, and the drop
      // target for the top level under them.
      await pump(
        tester,
        objects: <ModelObject>[for (var i = 1; i <= 4; i++) _object(i)],
      );
      expect(tester.getSize(find.byType(Outliner)).height, 5 * row);
    });

    testWidgets('the eye asks to hide, and asks again to show', (
      WidgetTester tester,
    ) async {
      final asked = <(int, bool)>[];
      await pump(
        tester,
        objects: <ModelObject>[_object(1), _object(2, visible: false)],
        onVisible: (int id, bool to) => asked.add((id, to)),
      );

      await tester.tap(find.byTooltip('Hide'));
      await tester.tap(find.byTooltip('Show'));
      await tester.pump();

      expect(asked, <(int, bool)>[(1, false), (2, true)]);
    });

    testWidgets('a double-click renames in place', (WidgetTester tester) async {
      final renamed = <(int, String)>[];
      await pump(
        tester,
        objects: <ModelObject>[_object(1)],
        onRename: (int id, String to) => renamed.add((id, to)),
      );

      // Mutation: leave renaming to the panel's own name field, which only
      // ever holds the one selected object. Renaming five objects is then
      // five selections and five trips to the other end of the panel.
      await tester.tap(find.text('o1'));
      // A real double click, not two taps at the same instant: a
      // `DoubleTapGestureRecognizer` refuses a second tap that arrives
      // sooner than `kDoubleTapMinTime`, so two `tap`s with no time between
      // them are two single clicks and the rename never starts.
      await tester.pump(const Duration(milliseconds: 60));
      await tester.tap(find.text('o1'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'torso');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(renamed, <(int, String)>[(1, 'torso')]);
    });
  });
}
