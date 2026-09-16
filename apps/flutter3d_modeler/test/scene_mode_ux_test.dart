/// `ux-23`'s own three: a panel narrow enough to cut a label, a light that
/// lands where it can be seen, and a rail that says what the mode has in it.
///
///     flutter test test/scene_mode_ux_test.dart
library;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter3d_editor_widgets/flutter3d_editor_widgets.dart';
import 'package:flutter3d_mesh/flutter3d_mesh.dart';
import 'package:flutter3d_model_core/flutter3d_model_core.dart';
import 'package:flutter3d_modeler/src/ui/shell.dart';
import 'package:flutter3d_modeler/src/ui/theme.dart';
import 'package:flutter3d_modeler/src/ui/tools.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart' as vm show Matrix4, Vector3;

/// One slider row inside a panel [width] wide — the shape a scene panel is.
Future<void> pumpRow(WidgetTester tester, double width) async {
  tester.view
    ..physicalSize = const Size(1440, 900)
    ..devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: modelerTheme(),
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: width,
            child: RangeSliderField(
              label: 'Ambient',
              value: 0.5,
              min: 0,
              max: 1,
              onChanged: (_) {},
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  group('ux-23: a label a person can read', () {
    testWidgets('at a 250-pixel panel the label is not cut', (
      WidgetTester tester,
    ) async {
      await pumpRow(tester, 250);

      // Mutation: keep the label beside the slider at every width. The review
      // found "Ambient" reading as "Am" — a 96-pixel column beside a slider
      // and a value box inside 250 leaves the label nothing, and the first
      // thing a person loses is the name of the thing they are dragging.
      final RenderParagraph text = tester.renderObject(find.text('Ambient'));
      expect(
        text.size.width,
        greaterThanOrEqualTo(text.getMinIntrinsicWidth(double.infinity)),
        reason: 'the label had room for all of itself',
      );
      expect(text.didExceedMaxLines, isFalse);
    });

    testWidgets('and at a wide one it stays beside the slider', (
      WidgetTester tester,
    ) async {
      await pumpRow(tester, 600);
      final double wide = tester.getTopLeft(find.text('Ambient')).dy;

      await pumpRow(tester, 250);
      final double narrow = tester.getTopLeft(find.text('Ambient')).dy;

      // Mutation: stack at every width. A wide panel then spends a line per
      // row on a label that fitted beside it, and shows two thirds as many
      // rows for nothing.
      expect(narrow, lessThan(wide));
    });
  });

  group('ux-23: a light where it can be seen', () {
    ModelProject cube() => const ModelProject().added(
      (int id) => ModelObject(
        id: id,
        name: 'cube',
        geometry: EditedGeometry(EditMesh.cuboid()),
        transform: vm.Matrix4.identity(),
      ),
    );

    test('a light added at a point lands there', () {
      final ModelHistory history = ModelHistory(cube());

      expect(history.run(AddLight(at: vm.Vector3(0, 3, 2))), isNull);

      // Mutation: ignore the argument, which is what this did. Every new
      // light landed at the origin — inside the cube — so the viewport
      // showed no change at all and the first thing anybody had to do was
      // work out why.
      final vm.Vector3 where = history.project.lighting.lights.single.transform
          .getTranslation();
      expect(where, vm.Vector3(0, 3, 2));
    });

    test('and with no point given it is where it always was', () {
      final ModelHistory history = ModelHistory(cube());
      expect(history.run(const AddLight()), isNull);

      // An agent, or a journal written before the argument existed.
      expect(
        history.project.lighting.lights.single.transform.getTranslation(),
        vm.Vector3.zero(),
      );
    });

    test('the point survives the journal', () {
      final AddLight command = AddLight(at: vm.Vector3(1, 2, 3));
      final ModelCommand? read = modelCommandFromJson(command.toJson());

      // Mutation: leave `at` out of `arguments`. A cold replay then puts
      // every light back at the origin, and a project rebuilt from its own
      // journal is lit differently from the one that was saved.
      expect(read, isA<AddLight>());
      expect((read! as AddLight).at, vm.Vector3(1, 2, 3));
    });
  });

  group('ux-23: a rail that is not empty', () {
    testWidgets('scene mode lists the lights it has', (
      WidgetTester tester,
    ) async {
      tester.view
        ..physicalSize = const Size(1440, 900)
        ..devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      var picked = -1;
      await tester.pumpWidget(
        MaterialApp(
          theme: modelerTheme(),
          home: ModelerShell(
            mode: ModelerMode.scene,
            onMode: (_) {},
            submode: MeshSubmode.vertex,
            onSubmode: (_) {},
            animationSubmode: AnimationSubmode.pose,
            onAnimationSubmode: (_) {},
            activeTool: null,
            onTool: (_) {},
            viewport: const SizedBox.expand(),
            properties: const Text('properties'),
            status: const Text('status'),
            railExtras: <RailEntry>[
              for (var at = 0; at < 2; at++)
                (
                  label: 'Light ${at + 1} · directional',
                  icon: Icons.wb_sunny_outlined,
                  armed: at == 0,
                  onPressed: () => picked = at,
                ),
            ],
          ),
        ),
      );

      // Mutation: draw the tools alone, which is what the rail did — and
      // scene mode has none, so the one mode whose whole subject is a short
      // list of things showed an empty column beside it.
      expect(find.byTooltip('Light 1 · directional'), findsOneWidget);
      expect(find.byTooltip('Light 2 · directional'), findsOneWidget);

      await tester.tap(find.byTooltip('Light 2 · directional'));
      await tester.pump();
      expect(picked, 1);
    });

    testWidgets('and every other mode\'s rail is what it was', (
      WidgetTester tester,
    ) async {
      tester.view
        ..physicalSize = const Size(1440, 900)
        ..devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: modelerTheme(),
          home: ModelerShell(
            mode: ModelerMode.object,
            onMode: (_) {},
            submode: MeshSubmode.vertex,
            onSubmode: (_) {},
            animationSubmode: AnimationSubmode.pose,
            onAnimationSubmode: (_) {},
            activeTool: null,
            onTool: (_) {},
            viewport: const SizedBox.expand(),
            properties: const Text('properties'),
            status: const Text('status'),
          ),
        ),
      );

      expect(
        find.byType(IconButton),
        findsNWidgets(toolsFor(ModelerMode.object).length),
      );
    });
  });
}
