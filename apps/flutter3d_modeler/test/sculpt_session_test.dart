/// `SculptSession` and the sculpting mode's own layout — `pro-sc-08`,
/// `ui-29`, `view-21`.
///
/// Driven end to end against a real `ModelerCubit` and a real
/// (software-rasterised) `ModelerStage`, the same shape
/// `weight_paint_session_test.dart` already drives its own session with.
///
///     flutter test test/sculpt_session_test.dart
library;

import 'package:flutter/material.dart' hide Material;
import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_cpu/testing.dart';
import 'package:flutter3d_mesh/flutter3d_mesh.dart';
import 'package:flutter3d_model_core/flutter3d_model_core.dart' hide Outcome;
import 'package:flutter3d_modeler/l10n/app_localizations.dart';
import 'package:flutter3d_modeler/src/element_picking.dart' show PickingView;
import 'package:flutter3d_modeler/src/input_policy.dart';
import 'package:flutter3d_modeler/src/modeler_cubit.dart';
import 'package:flutter3d_modeler/src/orbit_gestures.dart' show PointerKind;
import 'package:flutter3d_modeler/src/sculpt_session.dart';
import 'package:flutter3d_modeler/src/settings.dart' show Workspace;
import 'package:flutter3d_modeler/src/staging.dart';
import 'package:flutter3d_modeler/src/ui/sculpt_panel.dart';
import 'package:flutter3d_modeler/src/ui/tools.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart' as vm;

({ModelerCubit cubit, SculptSession session, EditMesh mesh, int objectId})
openedWith({vm.Matrix4? transform}) {
  final it = cpuTestDevice(width: 8, height: 8);
  // Two levels of subdivision: a bare cuboid has eight vertices and a brush
  // that reaches a quarter of it says nothing about a brush being local.
  final EditMesh mesh = catmullClark(
    EditMesh.cuboid(size: vm.Vector3(2, 2, 2)),
    levels: 2,
  )..clearJournal();
  final project = ModelProject(
    objects: <ModelObject>[
      ModelObject(
        id: 2,
        name: 'cube',
        geometry: EditedGeometry(mesh),
        transform: transform ?? vm.Matrix4.identity(),
      ),
    ],
    nextId: 3,
  );
  final history = ModelHistory(project)
    ..selection = const ProjectSelection(objects: <int>[2]);
  final stage = ModelerStage.fromProject(
    device: it.device,
    project: history.project,
  );
  stage.frameSubject();
  final cubit = ModelerCubit()
    ..opened(
      history,
      renderer: Renderer.create(device: it.device),
      stage: stage,
    );
  final session = SculptSession(
    cubit: cubit,
    history: () => (cubit.state as ModelerReady).history,
  );
  return (cubit: cubit, session: session, mesh: mesh, objectId: 2);
}

ModelerReady ready(ModelerCubit cubit) => cubit.state as ModelerReady;

PickingView view(ModelerCubit cubit) =>
    PickingView(camera: ready(cubit).stage.camera, size: const Size(800, 600));

const Offset middle = Offset(400, 300);

bool down(
  SculptSession session,
  ModelerCubit cubit, {
  BrushKind kind = BrushKind.draw,
  double strength = 0.5,
  bool symmetryX = false,
  bool inverted = false,
  Offset at = middle,
}) => session.pointerDown(
  view: view(cubit),
  at: at,
  objectId: 2,
  kind: kind,
  radiusPixels: kSculptCursorDiameter / 2,
  strength: strength,
  falloff: BrushFalloff.smooth,
  symmetryX: symmetryX,
  inverted: inverted,
);

bool move(
  SculptSession session,
  ModelerCubit cubit,
  Offset at, {
  BrushKind kind = BrushKind.draw,
  double strength = 0.5,
}) => session.pointerMove(
  view: view(cubit),
  at: at,
  kind: kind,
  radiusPixels: kSculptCursorDiameter / 2,
  strength: strength,
  falloff: BrushFalloff.smooth,
  symmetryX: false,
  inverted: false,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('view-21: a frame of samples is one stroke', () {
    test('a frame of samples runs one command, not one per sample', () {
      // The half of `view-21` that was left open: a stylus reports a few
      // hundred samples a second and a screen draws sixty, so what happens
      // between two drawn frames should be one stroke however many times the
      // pen moved. Nothing runs here until the frame flushes.
      //
      // Measured on the mesh rather than on the undo stack, because the stack
      // cannot answer this: the drag holds a transaction open, so every step
      // inside it folds into one and `history.steps` stays empty until the
      // pointer comes up whichever way the samples ran.
      final made = openedWith();
      expect(down(made.session, made.cubit), isTrue);
      // Read after the pointer is down, because opening the transaction marks
      // the mesh's own journal and that alone moves these bytes.
      final before = made.mesh.toBytes();
      for (var i = 1; i <= 5; i++) {
        move(made.session, made.cubit, middle + Offset(i.toDouble(), 0));
      }
      // Six samples in, and the mesh has not moved.
      expect(made.mesh.toBytes(), before);

      made.session.flush();
      expect(made.mesh.toBytes(), isNot(before));
    });

    test('and it lands within a hair of a stroke-per-sample drag', () {
      // The claim that makes the batching safe rather than merely cheaper.
      // `SculptStroke.apply` walks its points in order, multiplying each
      // one's pressure into the strength — exactly what the wiring used to do
      // by hand, one stroke at a time — so the only difference left is the
      // radius: a batch carries one, and the samples in it wanted radii
      // spread by 0.0083%. That is what this measures, in the units that
      // matter: how far a vertex ends up from where the old path put it.
      final batched = openedWith();
      expect(down(batched.session, batched.cubit), isTrue);
      for (var i = 1; i <= 5; i++) {
        move(batched.session, batched.cubit, middle + Offset(i.toDouble(), 0));
      }
      batched.session.pointerUp();

      final apiece = openedWith();
      expect(down(apiece.session, apiece.cubit), isTrue);
      apiece.session.flush();
      for (var i = 1; i <= 5; i++) {
        move(apiece.session, apiece.cubit, middle + Offset(i.toDouble(), 0));
        apiece.session.flush();
      }
      apiece.session.pointerUp();

      var worst = 0.0;
      final a = vm.Vector3.zero();
      final b = vm.Vector3.zero();
      for (var v = 0; v < batched.mesh.vertexSlotCount; v++) {
        if (!batched.mesh.isVertexAlive(v)) continue;
        batched.mesh.positionOf(v, a);
        apiece.mesh.positionOf(v, b);
        final double apart = (a - b).length;
        if (apart > worst) worst = apart;
      }
      // The cube is two units across and the brush is 0.4 wide; a vertex
      // moved by less than a ten-thousandth of that is a difference no
      // rendered frame can carry. Measured rather than asserted loosely: the
      // number this fixture produces is 2.7e-5.
      expect(worst, lessThan(1e-4));
      // And not a tautology — the drag really did move the mesh.
      expect(batched.mesh.toBytes(), isNot(openedWith().mesh.toBytes()));
    });

    test('a drag that ends between two frames still runs', () {
      // `pointerUp` flushes, because a pen leaving the tablet between two
      // drawn frames is the ordinary case and losing that frame's samples
      // would be a stroke that visibly stops short of where it was released.
      final made = openedWith();
      expect(down(made.session, made.cubit), isTrue);
      move(made.session, made.cubit, middle + const Offset(6, 0));
      made.session.pointerUp();

      expect(ready(made.cubit).history.steps, hasLength(1));
      expect(ready(made.cubit).history.undoSays, 'sculpt');
    });

    test('pressure rides its own list, so two presses are one stroke', () {
      // What made batching impossible before: the force was multiplied into
      // the strength at the call site, so two samples pressed differently
      // were two strokes with different strengths and nothing could group
      // them. `SculptStroke` has always computed `strength * pressure`
      // itself; the wiring now says it there.
      final made = openedWith();
      expect(
        made.session.pointerDown(
          view: view(made.cubit),
          at: middle,
          objectId: 2,
          kind: BrushKind.draw,
          radiusPixels: kSculptCursorDiameter / 2,
          strength: 0.5,
          falloff: BrushFalloff.smooth,
          symmetryX: false,
          inverted: false,
          pressure: 0.25,
        ),
        isTrue,
      );
      made.session.pointerMove(
        view: view(made.cubit),
        at: middle + const Offset(2, 0),
        kind: BrushKind.draw,
        radiusPixels: kSculptCursorDiameter / 2,
        strength: 0.5,
        falloff: BrushFalloff.smooth,
        symmetryX: false,
        inverted: false,
        pressure: 1.0,
      );
      made.session.pointerUp();

      expect(ready(made.cubit).history.steps, hasLength(1));
    });
  });

  group('a drag is one step', () {
    test('however many samples it is made of', () {
      final made = openedWith();
      expect(down(made.session, made.cubit), isTrue);
      for (var i = 1; i <= 5; i++) {
        move(made.session, made.cubit, middle + Offset(i * 3, 0));
      }
      made.session.pointerUp();

      // **`ui-29`'s own "a stroke — a transaction".** Mutation: run each
      // sample through `history.run` without opening a transaction. Six
      // presses of ⌘Z to take back one gesture, which is the single most
      // complained-about behaviour a tool can have.
      expect(ready(made.cubit).history.steps, hasLength(1));
      expect(ready(made.cubit).history.undoSays, 'sculpt');
    });

    test('and undo takes the whole gesture back, byte for byte', () {
      final made = openedWith();
      final before = made.mesh.toBytes();

      expect(down(made.session, made.cubit), isTrue);
      move(made.session, made.cubit, middle + const Offset(6, 0));
      made.session.pointerUp();
      expect(made.mesh.toBytes(), isNot(before));

      expect(ready(made.cubit).history.undo(), isTrue);
      expect(made.mesh.toBytes(), before);
    });

    test('a stroke that never touched the mesh leaves no step at all', () {
      final made = openedWith();
      // Far outside the cube, in a corner of the viewport the ray misses.
      expect(down(made.session, made.cubit, at: const Offset(4, 4)), isFalse);
      made.session.pointerUp();
      expect(ready(made.cubit).history.steps, isEmpty);
      expect(ready(made.cubit).history.canUndo, isFalse);
    });
  });

  group('where the stroke lands', () {
    test('on the mesh even when the object has been moved', () {
      // **World in, object out.** Mutation: pass the world hit straight to
      // `SculptStroke.points`. On a model at the origin nothing changes; on
      // this one, three metres along X, every stroke lands three metres off
      // the surface and moves nothing at all.
      final made = openedWith(
        transform: vm.Matrix4.translation(vm.Vector3(3, 0, 0)),
      );
      final before = made.mesh.toBytes();
      expect(down(made.session, made.cubit), isTrue);
      made.session.pointerUp();
      expect(made.mesh.toBytes(), isNot(before));
    });

    test('and an inverted stylus cuts in where the pen would build up', () {
      final made = openedWith();

      expect(down(made.session, made.cubit), isTrue);
      made.session.pointerUp();
      final int moved = _furthestMoved(made.mesh);
      final vm.Vector3 pushed = made.mesh.positionOf(moved).clone();
      expect(ready(made.cubit).history.undo(), isTrue);
      final vm.Vector3 rest = made.mesh.positionOf(moved).clone();
      final vm.Vector3 outward = pushed - rest;
      expect(outward.length, greaterThan(1e-6));

      expect(down(made.session, made.cubit, inverted: true), isTrue);
      made.session.pointerUp();
      final vm.Vector3 inward = made.mesh.positionOf(moved) - rest;

      // **The same stroke, the opposite effect** — the gesture every drawing
      // application on every platform already agrees on. Mutation: ignore
      // `ToolStroke.erase`. Flipping the pen over then builds the surface up
      // a second time, which reads as the application not noticing.
      expect(outward.dot(inward), lessThan(0));
    });
  });

  group('the layout', () {
    testWidgets('has a brush for each of the eight, and arms one', (
      WidgetTester tester,
    ) async {
      BrushKind? armed;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SculptPalette(
              armed: BrushKind.draw,
              onBrush: (BrushKind kind) => armed = kind,
            ),
          ),
        ),
      );

      for (final BrushKind kind in kSculptBrushes) {
        expect(
          find.byKey(ValueKey<String>('sculptBrush-${kind.name}')),
          findsOneWidget,
          reason: 'the palette is missing ${kind.name}',
        );
      }
      await tester.tap(find.byKey(const ValueKey<String>('sculptBrush-clay')));
      expect(armed, BrushKind.clay);
    });

    testWidgets('the card offers Subdivide, and says why when it cannot', (
      WidgetTester tester,
    ) async {
      var subdivided = 0;
      Widget card({String? refusal}) => MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SculptPanel(
            radius: kSculptCursorDiameter,
            onRadius: (double _) {},
            strength: 0.5,
            onStrength: (double _) {},
            falloff: BrushFalloff.smooth,
            onFalloff: (BrushFalloff _) {},
            symmetryX: false,
            onSymmetryX: (bool _) {},
            onSubdivide: () => subdivided++,
            faces: 384,
            subdivideRefusal: refusal,
          ),
        ),
      );

      await tester.pumpWidget(card());
      expect(find.text('384 faces'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey<String>('sculptSubdivide')));
      expect(subdivided, 1);

      // **A disabled button that says nothing is a button nobody can act
      // on.** Mutation: hide Subdivide when it cannot run. A person then
      // looks for a control that is not there instead of reading why the
      // one in front of them is off.
      await tester.pumpWidget(
        card(refusal: 'A subdivision does not carry shape keys with it'),
      );
      await tester.tap(find.byKey(const ValueKey<String>('sculptSubdivide')));
      expect(subdivided, 1);
    });
  });

  group('the mode', () {
    test('offers eight brushes and every one of them is a stroke tool', () {
      final List<ModelerTool> tools = toolsFor(ModelerMode.sculpt);
      expect(tools, hasLength(8));
      for (final ModelerTool tool in tools) {
        // `ui-29`: "touch doesn't create a stroke" is `InputPolicy` reading
        // this set. A brush left out of it would take a finger off the
        // camera and paint with it, which is the one thing that row forbids.
        expect(kStrokeTools, contains(tool.id));
        expect(brushKindOf(tool.id).name, tool.id.split('.').last);
        expect(sculptToolOf(brushKindOf(tool.id)), tool.id);
      }
    });

    test('a finger orbits and a stylus sculpts', () {
      const InputPolicy policy = InputPolicy();
      expect(
        policy.classify(kind: PointerKind.touch, tool: ToolCategory.sculpting),
        isA<CameraInput>(),
      );
      expect(
        policy.classify(
          kind: PointerKind.stylus,
          tool: ToolCategory.sculpting,
          pressure: 0.4,
        ),
        isA<ToolStroke>().having((ToolStroke it) => it.force, 'force', 0.4),
      );
    });

    test('and it is a mode the switcher will now offer', () {
      expect(ModelerMode.sculpt.ready, isTrue);
      expect(modesFor(Workspace.full), contains(ModelerMode.sculpt));
      // Not in Essential: "open a model, paint it, export it" is what most
      // people who open a modeller are doing, and sculpting is not on that
      // path — `ux-37`'s own rule.
      expect(
        modesFor(Workspace.essential),
        isNot(contains(ModelerMode.sculpt)),
      );
    });
  });
}

/// The vertex of [mesh] furthest from the origin — on a subdivided cube
/// sculpted once in the middle of one face, whichever the brush pushed
/// hardest.
int _furthestMoved(EditMesh mesh) {
  var best = 0;
  var bestLength = -1.0;
  final at = vm.Vector3.zero();
  for (var v = 0; v < mesh.vertexSlotCount; v++) {
    if (!mesh.isVertexAlive(v)) continue;
    mesh.positionOf(v, at);
    if (at.length > bestLength) {
      bestLength = at.length;
      best = v;
    }
  }
  return best;
}
