/// `mat-04a-n`'s own panel: a list of the project's materials, and — for the
/// one an object is painted with — base colour, metallic, roughness and one
/// texture slot.
///
///     flutter test test/material_panel_test.dart
library;

import 'package:flutter/material.dart';
import 'package:flutter3d_formats/flutter3d_formats.dart';
import 'package:flutter3d_model_core/flutter3d_model_core.dart';
import 'package:flutter3d_modeler/src/ui/material_panel.dart';
import 'package:flutter3d_modeler/src/ui/theme.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

ProjectMaterial _material({String? name, double metallic = 0.0}) =>
    ProjectMaterial(
      surface: SurfaceMaterial(name: name, metallic: metallic),
    );

Future<void> _pump(
  WidgetTester tester, {
  required List<ProjectMaterial> materials,
  int? activeIndex,
  ValueChanged<int?>? onAssign,
  VoidCallback? onAddMaterial,
  void Function(String field, Object? value)? onSetField,
  bool metallicEnabled = true,
  VoidCallback? onChooseBaseColorTexture,
  VoidCallback? onClearBaseColorTexture,
  String? textureName,
}) => tester.pumpWidget(
  MaterialApp(
    theme: modelerTheme(),
    home: Scaffold(
      body: MaterialPanel(
        materials: materials,
        activeIndex: activeIndex,
        onAssign: onAssign ?? (_) {},
        onAddMaterial: onAddMaterial ?? () {},
        onSetField: onSetField ?? (_, _) {},
        metallicEnabled: metallicEnabled,
        onChooseBaseColorTexture: onChooseBaseColorTexture ?? () {},
        onClearBaseColorTexture: onClearBaseColorTexture,
        textureName: textureName,
      ),
    ),
  ),
);

void main() {
  group('the material list', () {
    testWidgets('shows every material, and marks the active one', (
      WidgetTester tester,
    ) async {
      await _pump(
        tester,
        materials: <ProjectMaterial>[
          _material(name: 'Steel'),
          _material(name: 'Rust'),
        ],
        activeIndex: 1,
      );

      expect(find.text('Steel'), findsOneWidget);
      expect(find.text('Rust'), findsOneWidget);
      final Semantics rustRow = tester
          .widgetList<Semantics>(find.byType(Semantics))
          .firstWhere((Semantics s) => s.properties.label == 'Rust');
      expect(rustRow.properties.selected, isTrue);
    });

    testWidgets('tapping a different row assigns it', (
      WidgetTester tester,
    ) async {
      final assigned = <int?>[];
      await _pump(
        tester,
        materials: <ProjectMaterial>[
          _material(name: 'Steel'),
          _material(name: 'Rust'),
        ],
        activeIndex: 0,
        onAssign: assigned.add,
      );

      await tester.tap(find.text('Rust'));
      await tester.pump();

      expect(assigned, <int?>[1]);
    });

    testWidgets('tapping the row already active clears the paint', (
      WidgetTester tester,
    ) async {
      final assigned = <int?>[];
      await _pump(
        tester,
        materials: <ProjectMaterial>[_material(name: 'Steel')],
        activeIndex: 0,
        onAssign: assigned.add,
      );

      await tester.tap(find.text('Steel'));
      await tester.pump();

      expect(assigned, <int?>[null]);
    });

    testWidgets('the "Add material" link is always there', (
      WidgetTester tester,
    ) async {
      var added = 0;
      await _pump(
        tester,
        materials: const <ProjectMaterial>[],
        onAddMaterial: () => added++,
      );

      expect(find.text('No materials'), findsOneWidget);
      await tester.tap(find.text('Add material'));
      expect(added, 1);
    });
  });

  group('the active material\'s own fields', () {
    testWidgets('mat-04\'s own acceptance: Lambert disables metallic', (
      WidgetTester tester,
    ) async {
      final metallic = <double>[];
      await _pump(
        tester,
        materials: <ProjectMaterial>[_material(name: 'Cloth', metallic: 0.2)],
        activeIndex: 0,
        metallicEnabled: false,
        onSetField: (String field, Object? value) {
          if (field == 'metallic') metallic.add(value! as double);
        },
      );

      final metallicFinder = find.byKey(
        const ValueKey<String>('slider-Metallic'),
      );
      final Slider slider = tester.widget(metallicFinder);
      expect(slider.onChanged, isNull);
      expect(slider.onChangeEnd, isNull);

      // Dragging a slider with no handler wired does nothing at all.
      await tester.drag(metallicFinder, const Offset(60, 0));
      await tester.pumpAndSettle();
      expect(metallic, isEmpty);
    });

    testWidgets('a metal keeps its metallic slider live', (
      WidgetTester tester,
    ) async {
      final metallic = <double>[];
      await _pump(
        tester,
        materials: <ProjectMaterial>[_material(name: 'Steel', metallic: 0.2)],
        activeIndex: 0,
        onSetField: (String field, Object? value) {
          if (field == 'metallic') metallic.add(value! as double);
        },
      );

      final metallicFinder = find.byKey(
        const ValueKey<String>('slider-Metallic'),
      );
      final Slider slider = tester.widget(metallicFinder);
      expect(slider.onChanged, isNotNull);

      await tester.drag(metallicFinder, const Offset(60, 0));
      await tester.pumpAndSettle();

      // Mutation: call `onSetField` from the slider's continuous `onChanged`
      // instead of only from `onChangeEnd`. One drag, one step of undo.
      expect(metallic, hasLength(1));
    });

    testWidgets('the base colour field edits `baseColor`', (
      WidgetTester tester,
    ) async {
      final said = <List<double>>[];
      await _pump(
        tester,
        materials: <ProjectMaterial>[
          ProjectMaterial(
            surface: SurfaceMaterial(baseColor: Vector4(1, 1, 1, 1)),
          ),
        ],
        activeIndex: 0,
        onSetField: (String field, Object? value) {
          if (field == 'baseColor') said.add(value! as List<double>);
        },
      );

      await tester.enterText(find.byType(TextField), '5FD4E4');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();

      expect(said, hasLength(1));
      expect(said.single[0], closeTo(0.373, 0.001));
    });

    testWidgets('the texture row shows its own image name', (
      WidgetTester tester,
    ) async {
      await _pump(
        tester,
        materials: <ProjectMaterial>[_material(name: 'Steel')],
        activeIndex: 0,
        textureName: 'rust.png',
        onClearBaseColorTexture: () {},
      );

      expect(find.text('rust.png'), findsOneWidget);
      expect(find.text('Clear'), findsOneWidget);
    });

    testWidgets('an empty texture slot offers no "Clear"', (
      WidgetTester tester,
    ) async {
      await _pump(
        tester,
        materials: <ProjectMaterial>[_material(name: 'Steel')],
        activeIndex: 0,
      );

      expect(find.text('None'), findsOneWidget);
      expect(find.text('Clear'), findsNothing);
    });

    testWidgets('"Choose…" reaches the caller', (WidgetTester tester) async {
      var chosen = 0;
      await _pump(
        tester,
        materials: <ProjectMaterial>[_material(name: 'Steel')],
        activeIndex: 0,
        onChooseBaseColorTexture: () => chosen++,
      );

      await tester.tap(find.text('Choose…'));
      expect(chosen, 1);
    });

    testWidgets('no active material shows no field, only the list', (
      WidgetTester tester,
    ) async {
      await _pump(
        tester,
        materials: <ProjectMaterial>[_material(name: 'Steel')],
        activeIndex: null,
      );

      expect(find.text('Steel'), findsOneWidget);
      expect(find.byType(Slider), findsNothing);
      expect(find.text('Base colour texture'), findsNothing);
    });
  });
}
