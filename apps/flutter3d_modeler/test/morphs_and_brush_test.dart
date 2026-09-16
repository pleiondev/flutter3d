/// `ux-24`'s own two: a shape key that moves the model rather than the
/// markers, and a brush whose reach is visible before the stroke.
///
///     flutter test test/morphs_and_brush_test.dart
library;

import 'dart:typed_data';

import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart' hide Material;
import 'package:flutter/services.dart';
import 'package:flutter3d/flutter3d.dart' hide Material;
import 'package:flutter3d_cpu/testing.dart';
import 'package:flutter3d_mesh/flutter3d_mesh.dart';
import 'package:flutter3d_model_core/flutter3d_model_core.dart' hide Outcome;
import 'package:flutter3d_modeler/src/modeler_viewport.dart';
import 'package:flutter3d_modeler/src/scene_sync.dart';
import 'package:flutter3d_modeler/src/settings.dart' show KeymapPreset;
import 'package:flutter3d_modeler/src/staging.dart';
import 'package:flutter3d_modeler/src/ui/keymap.dart';
import 'package:flutter3d_modeler/src/ui/modeler_keys.dart';
import 'package:flutter3d_modeler/src/ui/theme.dart';
import 'package:flutter3d_modeler/src/ui/tools.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart' as vm show Matrix4, Vector3;

/// A cube, and one shape key over it that lifts every vertex a metre.
({EditMesh mesh, ShapeKey key}) _cubeAndKey() {
  final EditMesh mesh = EditMesh.cuboid();
  final Float32List lifted = Float32List(mesh.vertexSlotCount * 3);
  final vm.Vector3 at = vm.Vector3.zero();
  for (var vertex = 0; vertex < mesh.vertexSlotCount; vertex++) {
    mesh.positionOf(vertex, at);
    lifted[vertex * 3] = at.x;
    lifted[vertex * 3 + 1] = at.y + 1.0;
    lifted[vertex * 3 + 2] = at.z;
  }
  return (mesh: mesh, key: ShapeKey('up', lifted));
}

ModelProject _cubeWithShape({double weight = 0.0}) {
  final ({EditMesh mesh, ShapeKey key}) it = _cubeAndKey();
  return const ModelProject().added(
    (int id) => ModelObject(
      id: id,
      name: 'cube',
      geometry: EditedGeometry(it.mesh),
      transform: vm.Matrix4.identity(),
      shapeSet: ShapeSet(keys: <ShapeKey>[it.key], weights: <double>[weight]),
    ),
  );
}

/// The highest Y any vertex of [data] sits at.
double _topOf(MeshData data) {
  final int stride = data.layout.floatsPerVertex;
  final int offset = data.layout.floatOffsetOf('position');
  var top = double.negativeInfinity;
  for (var at = offset; at + 2 < data.vertices.length; at += stride) {
    final double y = data.vertices[at + 1];
    if (y > top) top = y;
  }
  return top;
}

void main() {
  group('ux-24: a shape key moves the model', () {
    test('at weight one the buffer is where the key puts it', () {
      final ({EditMesh mesh, ShapeKey key}) it = _cubeAndKey();
      final MeshData base = it.mesh.toMeshData();

      final MeshData lifted = morphedForPreview(
        ShapeSet(keys: <ShapeKey>[it.key], weights: const <double>[1.0]),
        base,
        it.mesh,
      );

      // Mutation: upload `EditedGeometry.mesh` straight through, which is
      // what this did. The slider moved the document and the markers over
      // the model, and left the model itself exactly where it was — so the
      // one thing a morph is for was the one thing it did not do.
      expect(_topOf(lifted), closeTo(_topOf(base) + 1.0, 1e-5));
    });

    test('and at weight nought it is exactly the base, untouched', () {
      final ({EditMesh mesh, ShapeKey key}) it = _cubeAndKey();
      final MeshData base = it.mesh.toMeshData();

      final MeshData rested = morphedForPreview(
        ShapeSet(keys: <ShapeKey>[it.key], weights: const <double>[0.0]),
        base,
        it.mesh,
      );

      // The same instance: an object nobody has morphed pays nothing at all,
      // which is almost every object.
      expect(identical(rested, base), isTrue);
      expect(
        identical(morphedForPreview(const ShapeSet(), base, it.mesh), base),
        isTrue,
      );
    });

    test('half a weight is half the way there', () {
      final ({EditMesh mesh, ShapeKey key}) it = _cubeAndKey();
      final MeshData base = it.mesh.toMeshData();

      final MeshData half = morphedForPreview(
        ShapeSet(keys: <ShapeKey>[it.key], weights: const <double>[0.5]),
        base,
        it.mesh,
      );

      expect(_topOf(half), closeTo(_topOf(base) + 0.5, 1e-5));
    });

    test('a weight that moves re-uploads, and one that does not costs '
        'nothing', () {
      final it = cpuTestDevice(width: 8, height: 8);
      final Scene scene = Scene();
      final SceneNode root = SceneNode(name: 'root');
      scene.root.add(root);
      final SceneSync sync = SceneSync(
        device: it.device,
        scene: scene,
        root: root,
      );

      final ModelProject rested = _cubeWithShape();
      expect(sync.apply(rested), 1);
      // Nothing changed: no upload.
      expect(sync.apply(rested), 0);

      final ModelObject object = rested.objects.single;
      final ModelProject lifted = rested.withObject(
        object.copyWith(
          shapeSet: ShapeSet(
            keys: object.shapeSet.keys,
            weights: const <double>[1.0],
          ),
        ),
      );

      // Mutation: leave `shapeSet` out of the questions `apply` asks. A
      // weight moves neither the geometry instance nor the modifier list, so
      // the buffer would keep the base positions and the model would sit
      // still however far the slider went.
      expect(sync.apply(lifted), 1);
    });
  });

  group('ux-24: the brush says how far it reaches', () {
    Future<void> pump(
      WidgetTester tester, {
      double? radius,
      bool inverting = false,
    }) async {
      final it = cpuTestDevice(width: 64, height: 64);
      await tester.pumpWidget(
        MaterialApp(
          theme: modelerTheme(),
          home: Scaffold(
            body: SizedBox(
              width: 400,
              height: 400,
              child: ModelerViewport(
                renderer: Renderer.create(device: it.device),
                stage: ModelerStage.fromProject(
                  device: it.device,
                  project: const ModelProject(),
                ),
                onFrame: () {},
                brushRadius: radius,
                brushInverting: inverting,
              ),
            ),
          ),
        ),
      );
      await tester.pump();
    }

    testWidgets('a circle follows the pointer while a brush is armed', (
      WidgetTester tester,
    ) async {
      await pump(tester, radius: 48);

      // Nothing yet: the pointer has not been over the picture.
      expect(find.byType(CustomPaint), findsWidgets);

      final TestGesture pointer = await tester.createGesture(
        kind: PointerDeviceKind.mouse,
      );
      await pointer.addPointer(
        location: tester.getCenter(find.byType(ModelerViewport)),
      );
      addTearDown(pointer.removePointer);
      await pointer.moveTo(
        tester.getCenter(find.byType(ModelerViewport)) + const Offset(10, 10),
      );
      await tester.pump();

      // Mutation: draw nothing. The only way to find out what forty-eight
      // pixels covers on this model at this zoom is then to paint and undo.
      expect(
        find.byWidgetPredicate(
          (Widget it) =>
              it is CustomPaint && '${it.painter}'.contains('BrushPainter'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('and none at all with no brush armed', (
      WidgetTester tester,
    ) async {
      await pump(tester);

      expect(
        find.byWidgetPredicate(
          (Widget it) =>
              it is CustomPaint && '${it.painter}'.contains('BrushPainter'),
        ),
        findsNothing,
      );
    });
  });

  group('ux-24: the two keys that size it', () {
    testWidgets('[ narrows and ] widens', (WidgetTester tester) async {
      var narrower = 0;
      var wider = 0;
      final FocusNode content = FocusNode();
      addTearDown(content.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(platform: TargetPlatform.linux),
          home: ModelerKeys(
            onKey: (_, _) => false,
            onUndo: () {},
            onRedo: () {},
            onExport: () {},
            onTool: (_) {},
            mode: ModelerMode.animation,
            onLevel: (_) {},
            onAnimationLevel: (_) {},
            onSelectAll: () {},
            onSelectNone: () {},
            onInvertSelection: () {},
            onShortcutHelp: () {},
            onBrushNarrower: () => narrower++,
            onBrushWider: () => wider++,
            keymap: keymapFor(KeymapPreset.standard, apple: false),
            tools: toolsFor(ModelerMode.animation),
            child: Scaffold(
              body: Focus(focusNode: content, child: const SizedBox.shrink()),
            ),
          ),
        ),
      );
      content.requestFocus();
      await tester.pump();

      await tester.sendKeyEvent(LogicalKeyboardKey.bracketLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.bracketRight);
      await tester.pump();

      // Mutation: bind one key for both, or none at all. The radius is then
      // a number in a panel at the other end of the window, reached with the
      // hand that is holding the brush.
      expect(narrower, 1);
      expect(wider, 1);
    });
  });
}
