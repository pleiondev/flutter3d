/// `pro-uv-07`'s own wiring half, without a screen: what the UV mode reads
/// off a mesh, how often it reads it, and which commands its rail stands for.
///
///     flutter test test/uv_panel_state_test.dart
library;

import 'package:flutter3d_mesh/flutter3d_mesh.dart';
import 'package:flutter3d_model_core/flutter3d_model_core.dart';
import 'package:flutter3d_modeler/src/tool_commands.dart';
import 'package:flutter3d_modeler/src/uv_panel_state.dart';
import 'package:flutter3d_modeler/src/uv_unwrap_layout.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart' as vm;

/// A cube as a one-object project, selected, so a command has a target.
({ModelHistory history, EditMesh mesh}) _cube() {
  final EditMesh mesh = EditMesh.cuboid();
  final ModelProject project = const ModelProject().added(
    (int id) => ModelObject(
      id: id,
      name: 'cube',
      geometry: EditedGeometry(mesh),
      transform: vm.Matrix4.identity(),
    ),
  );
  final history = ModelHistory(project)
    ..selection = ProjectSelection(
      mode: SelectionMode.mesh,
      objects: <int>[project.objects.first.id],
      level: ElementLevel.edge,
    );
  return (history: history, mesh: mesh);
}

/// The same cube, cut along all twelve of its edges and unwrapped: six
/// faces, six islands. Every edge rather than a chosen few because a closed
/// surface with no seam does not unwrap at all — see the test that says so.
({ModelHistory history, EditMesh mesh}) _cutAndUnwrapped() {
  final (:history, :mesh) = _cube();
  history.selection = history.selection.copyWith(
    elements: Selection.all(mesh, ElementLevel.edge).ids.toList(),
  );
  expect(history.run(const MarkSeam()), isNull);
  expect(history.run(const UnwrapCommand()), isNull);
  return (history: history, mesh: mesh);
}

void main() {
  group('uvFillOf', () {
    test('is the area the triangles cover, not the box round them', () {
      // Half the unit square, as one right triangle whose bounding box is
      // all of it. Mutation: measure the box. An L-shaped island then
      // reports the corner it leaves empty as used.
      const half = UvIslandData(
        id: 0,
        faceCount: 1,
        stretch: 1,
        triangles: <UvTriangle>[
          UvTriangle(Offset.zero, Offset(1, 0), Offset(0, 1)),
        ],
      );
      expect(uvFillOf(const <UvIslandData>[half]), closeTo(0.5, 1e-9));
    });

    test('counts a mirrored island for what it covers', () {
      // The same triangle wound the other way round, which is what a
      // mirrored half of a model unwraps to. Mutation: sum signed areas —
      // this one cancels the one above and a full square reads as empty.
      const mirrored = UvIslandData(
        id: 0,
        faceCount: 1,
        stretch: 1,
        triangles: <UvTriangle>[
          UvTriangle(Offset.zero, Offset(0, 1), Offset(1, 0)),
        ],
      );
      expect(uvFillOf(const <UvIslandData>[mirrored]), closeTo(0.5, 1e-9));
    });

    test('never says more than the whole square', () {
      // An unpacked unwrap lays every island over every other. Three copies
      // of the whole square are still one square of texture.
      const whole = UvIslandData(
        id: 0,
        faceCount: 2,
        stretch: 1,
        triangles: <UvTriangle>[
          UvTriangle(Offset.zero, Offset(1, 0), Offset(1, 1)),
          UvTriangle(Offset.zero, Offset(1, 1), Offset(0, 1)),
        ],
      );
      expect(uvFillOf(const <UvIslandData>[whole, whole, whole]), 1.0);
      expect(uvFillOf(const <UvIslandData>[]), 0.0);
    });
  });

  group('UvPanelState.readingOf', () {
    test(
      'a mesh with no UVs has no islands, rather than six at the origin',
      () {
        final EditMesh mesh = EditMesh.cuboid();
        expect(mesh.hasLayer(MeshDomain.corner, MeshAttribute.uv0), isFalse);

        // Mutation: build islands regardless. `EditMesh.uvOf` answers zero for
        // every corner of a mesh with no layer, so the list says "one island"
        // about a mesh nobody has unwrapped.
        final UvReading reading = UvPanelState().readingOf(mesh, 1);
        expect(reading.islands, isEmpty);
        expect(reading.fill, 0);
      },
    );

    test(
      'a cube cut along every edge reads as six islands and their cover',
      () {
        final (:history, :mesh) = _cutAndUnwrapped();

        final UvReading reading = UvPanelState().readingOf(
          mesh,
          history.project.objects.first.version,
        );
        expect(reading.islands, hasLength(6));
        expect(reading.seams, hasLength(12));
        expect(reading.fill, greaterThan(0));
        expect(reading.fill, lessThanOrEqualTo(1));
      },
    );

    test('an unwrap that covers nothing reads as no unwrap at all', () {
      // A closed surface with no seam on it: `lscm` lays it out along a
      // line and `UnwrapCommand` calls that done. The layer exists, every
      // island has its triangles, and none of them has any area.
      //
      // Mutation: go by `hasLayer` alone. The panel lists one island about a
      // mesh whose every corner is at `u = 0` — and goes on listing it after
      // the unwrap is undone, since undo zeroes the UVs and leaves the layer.
      final (:history, :mesh) = _cube();
      expect(history.run(const UnwrapCommand()), isNull);
      expect(mesh.hasLayer(MeshDomain.corner, MeshAttribute.uv0), isTrue);

      final UvReading reading = UvPanelState().readingOf(mesh, 2);
      expect(reading.islands, isEmpty);
    });

    test('reads once per version, and again when the version moves', () {
      final (:history, :mesh) = _cutAndUnwrapped();
      final state = UvPanelState();
      final int version = history.project.objects.first.version;

      // Mutation: drop the cache. The two readings stop being the same
      // object, and the screen — which rebuilds on every tick — walks the
      // whole mesh sixty times a second.
      final UvReading first = state.readingOf(mesh, version);
      expect(
        identical(state.readingOf(mesh, version).islands, first.islands),
        isTrue,
      );

      // Clearing one seam joins two faces into one island, so the same mesh
      // at the next version is a different reading. Mutation: key the cache
      // on the mesh alone — an `EditMesh` is edited in place, so it is the
      // same object before and after, and the list never changes again.
      history.selection = history.selection.copyWith(
        elements: <int>[mesh.edgeOf(0)],
      );
      expect(history.run(const MarkSeam(on: false)), isNull);
      final int next = history.project.objects.first.version;
      expect(next, isNot(version));
      expect(state.readingOf(mesh, next).islands, hasLength(5));
    });

    test('a new reading puts the lit island out, and no mesh drops it all', () {
      final (history: _, :mesh) = _cutAndUnwrapped();
      final state = UvPanelState()
        ..readingOf(mesh, 1)
        ..selectedIsland = 2;

      // Island ids are positions in `splitIslands`' own list, and a seam
      // marked since renumbers them: island 2 of the old reading is some
      // other patch of the new one. Mutation: keep it. The list lights a
      // row the person never chose.
      state.readingOf(mesh, 2);
      expect(state.selectedIsland, isNull);

      state.selectedIsland = 1;
      expect(state.readingOf(null, 0), kNoUvReading);
      expect(state.selectedIsland, isNull);
    });
  });

  group('the UV rail', () {
    test('marks and clears through one command, both ways round', () {
      final ModelCommand? mark = commandFor(
        'uv.markSeam',
        activeObject: 1,
        editMesh: null,
      );
      final ModelCommand? clear = commandFor(
        'uv.clearSeam',
        activeObject: 1,
        editMesh: null,
      );

      // Mutation: map both to `MarkSeam()`. "Clear the seam" marks one.
      expect(mark, isA<MarkSeam>().having((MarkSeam it) => it.on, 'on', true));
      expect(
        clear,
        isA<MarkSeam>().having((MarkSeam it) => it.on, 'on', false),
      );
    });

    test('leaves unwrap and pack to the wiring, which knows the margin', () {
      // `commandFor` is handed what is selected and nothing else. A
      // `UnwrapCommand()` from here would run at the default margin whatever
      // the panel says.
      expect(commandFor('uv.unwrap', activeObject: 1, editMesh: null), isNull);
      expect(commandFor('uv.pack', activeObject: 1, editMesh: null), isNull);
    });

    test('a seam and its undo are one step each', () {
      final (:history, :mesh) = _cube();
      final int half = mesh.edgeOf(0);
      history.selection = history.selection.copyWith(elements: <int>[half]);

      expect(history.run(const MarkSeam()), isNull);
      expect(mesh.edgeHas(half, EdgeFlags.seam), isTrue);

      // One press of undo, not one per edge and not none.
      expect(history.undo(), isTrue);
      expect(mesh.edgeHas(half, EdgeFlags.seam), isFalse);
      expect(history.canUndo, isFalse);
    });
  });
}
