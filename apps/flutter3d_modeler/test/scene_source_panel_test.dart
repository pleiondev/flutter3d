/// `mat-24`'s own source panel: the light list, selection, and the fields
/// of whichever light is selected.
///
///     flutter test test/scene_source_panel_test.dart
library;

import 'package:flutter/material.dart';
import 'package:flutter3d_model_core/flutter3d_model_core.dart';
import 'package:flutter3d_modeler/src/ui/scene_source_panel.dart';
import 'package:flutter3d_modeler/src/ui/theme.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _pump(
  WidgetTester tester, {
  required List<ProjectLight> lights,
  int? selected,
  ValueChanged<int>? onSelect,
  VoidCallback? onAdd,
  ValueChanged<int>? onRemove,
  void Function(int, ProjectLightType)? onTypeChanged,
  void Function(int, double)? onIntensityChanged,
  void Function(int, double)? onRangeChanged,
  void Function(int, bool)? onShadowChanged,
  void Function(int, double)? onConeChanged,
}) => tester.pumpWidget(
  MaterialApp(
    theme: modelerTheme(),
    home: Scaffold(
      body: SceneSourcePanel(
        lights: lights,
        selected: selected,
        onSelect: onSelect ?? (_) {},
        onAdd: onAdd ?? () {},
        onRemove: onRemove ?? (_) {},
        onTypeChanged: onTypeChanged ?? (_, _) {},
        onIntensityChanged: onIntensityChanged ?? (_, _) {},
        onRangeChanged: onRangeChanged ?? (_, _) {},
        onShadowChanged: onShadowChanged ?? (_, _) {},
        onConeChanged: onConeChanged ?? (_, _) {},
      ),
    ),
  ),
);

void main() {
  testWidgets('an empty list says so, and offers no fields', (tester) async {
    await _pump(tester, lights: const <ProjectLight>[]);

    expect(find.text('No lights'), findsOneWidget);
    expect(find.text('SOURCE'), findsNothing);
  });

  testWidgets('each light shows its own kind', (tester) async {
    await _pump(
      tester,
      lights: <ProjectLight>[
        ProjectLight(type: ProjectLightType.point),
        ProjectLight(type: ProjectLightType.spot),
      ],
    );

    expect(find.text('Point'), findsOneWidget);
    expect(find.text('Spot'), findsOneWidget);
  });

  testWidgets('tapping a row reports its own index, not always zero', (
    tester,
  ) async {
    final selected = <int>[];
    await _pump(
      tester,
      lights: <ProjectLight>[ProjectLight(), ProjectLight()],
      onSelect: selected.add,
    );

    await tester.tap(find.byType(ListTile).last);

    expect(selected, <int>[1]);
  });

  testWidgets('the remove button names its own row, not the panel', (
    tester,
  ) async {
    final removed = <int>[];
    await _pump(
      tester,
      lights: <ProjectLight>[ProjectLight(), ProjectLight()],
      onRemove: removed.add,
    );

    await tester.tap(find.byIcon(Icons.close).last);

    // Mutation: wire every remove button to index 0. Two identical rows
    // would look the same and only the reported index tells them apart.
    expect(removed, <int>[1]);
  });

  testWidgets('the Add link is always present', (tester) async {
    var added = 0;
    await _pump(
      tester,
      lights: const <ProjectLight>[],
      onAdd: () => added++,
    );

    await tester.tap(find.widgetWithText(TextButton, 'Add'));
    expect(added, 1);
  });

  testWidgets('no field section when nothing is selected', (tester) async {
    await _pump(
      tester,
      lights: <ProjectLight>[ProjectLight()],
      selected: null,
    );

    expect(find.text('SOURCE'), findsNothing);
  });

  testWidgets('an out-of-range selection is treated as none', (tester) async {
    await _pump(
      tester,
      lights: <ProjectLight>[ProjectLight()],
      selected: 5,
    );

    // Mutation: index into `lights` with the raw `selected` value regardless
    // of range — this would throw building the widget instead of quietly
    // showing no field section.
    expect(find.text('SOURCE'), findsNothing);
  });

  testWidgets('the selected light shows its own intensity and range', (
    tester,
  ) async {
    await _pump(
      tester,
      lights: <ProjectLight>[
        ProjectLight(intensity: 2.5, range: 4.0),
      ],
      selected: 0,
    );

    expect(find.text('SOURCE'), findsOneWidget);
    expect(find.text('2.5'), findsOneWidget);
    expect(find.text('4'), findsOneWidget);
  });

  testWidgets('the cone field only appears for a spot light', (tester) async {
    await _pump(
      tester,
      lights: <ProjectLight>[ProjectLight(type: ProjectLightType.point)],
      selected: 0,
    );
    expect(find.text('Cone'), findsNothing);

    await _pump(
      tester,
      lights: <ProjectLight>[ProjectLight(type: ProjectLightType.spot)],
      selected: 0,
    );
    expect(find.text('Cone'), findsOneWidget);
  });

  testWidgets('changing intensity reports the selected index and the value', (
    tester,
  ) async {
    final changes = <(int, double)>[];
    await _pump(
      tester,
      lights: <ProjectLight>[ProjectLight(), ProjectLight(intensity: 1.0)],
      selected: 1,
      onIntensityChanged: (int i, double v) => changes.add((i, v)),
    );

    await tester.enterText(find.widgetWithText(TextField, '1').first, '3.5');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();

    expect(changes, <(int, double)>[(1, 3.5)]);
  });

  testWidgets('toggling shadow reports the selected index', (tester) async {
    final changes = <(int, bool)>[];
    await _pump(
      tester,
      lights: <ProjectLight>[ProjectLight()],
      selected: 0,
      onShadowChanged: (int i, bool v) => changes.add((i, v)),
    );

    await tester.tap(find.byType(Switch));

    expect(changes, <(int, bool)>[(0, true)]);
  });

  testWidgets('picking a type from the dropdown reports it', (tester) async {
    final changes = <(int, ProjectLightType)>[];
    await _pump(
      tester,
      lights: <ProjectLight>[ProjectLight(type: ProjectLightType.point)],
      selected: 0,
      onTypeChanged: (int i, ProjectLightType t) => changes.add((i, t)),
    );

    await tester.tap(find.byType(DropdownButton<ProjectLightType>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Spot').last);
    await tester.pumpAndSettle();

    expect(changes, <(int, ProjectLightType)>[(0, ProjectLightType.spot)]);
  });
}
