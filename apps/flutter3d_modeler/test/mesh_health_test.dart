/// `ux-16`'s own three: a panel that says what is wrong and fixes it, a
/// command that builds topology for an import, and a banner where mesh mode
/// has nothing to edit.
///
///     flutter test test/mesh_health_test.dart
library;

import 'dart:typed_data';

import 'package:flutter/material.dart' hide Material;
import 'package:flutter3d/flutter3d.dart' show MeshData, VertexLayout;
import 'package:flutter3d_mesh/flutter3d_mesh.dart';
import 'package:flutter3d_model_core/flutter3d_model_core.dart' hide Outcome;
import 'package:flutter3d_modeler/l10n/app_localizations.dart';
import 'package:flutter3d_modeler/src/tool_commands.dart';
import 'package:flutter3d_modeler/src/ui/mesh_health_panel.dart';
import 'package:flutter3d_modeler/src/ui/no_mesh_banner.dart';
import 'package:flutter3d_modeler/src/ui/theme.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart' as vm show Matrix4;

/// A cube with one face taken out of it — one hole, whose boundary is four
/// edges.
EditMesh _holed() {
  final EditMesh mesh = EditMesh.cuboid();
  // **Inside a step, because every write is.** `EditMesh` grew a journal
  // after this fixture was written and `deleteFace` now refuses outside one
  // — which is the right refusal and is what this helper had been getting
  // away with until the whole suite was run again.
  mesh.beginStep();
  for (var face = 0; face < mesh.faceSlotCount; face++) {
    if (!mesh.isFaceAlive(face)) continue;
    mesh.deleteFace(face);
    break;
  }
  mesh.endStep();
  return mesh;
}

/// Two triangles as an unwelded buffer — the shape an STL arrives in, where
/// every triangle carries its own three vertices.
MeshData _unwelded() => MeshData(
  layout: VertexLayout.standard,
  vertices: Float32List.fromList(<double>[
    for (final List<double> corner in <List<double>>[
      <double>[0, 0, 0],
      <double>[1, 0, 0],
      <double>[0, 1, 0],
      // The second triangle shares two corners with the first, written out
      // again — which is exactly what makes it unwelded.
      <double>[1, 0, 0],
      <double>[1, 1, 0],
      <double>[0, 1, 0],
    ]) ...<double>[
      ...corner,
      // **A whole standard vertex, not a position and five spare floats.**
      // This wrote three and then five once, which is twenty-three floats
      // for six vertices against a layout that asks for sixteen each, and
      // `MeshData` refuses that now rather than reading past the end.
      0, 0, 1,
      0, 0,
      1, 0, 0, 1,
      1, 1, 1, 1,
    ],
  ]),
  indices: Uint32List.fromList(<int>[0, 1, 2, 3, 4, 5]),
);

void main() {
  /// The labels are words now, so the one the button shows is asked for in
  /// the language the expectation is written in.
  late AppLocalizations english;

  setUpAll(() async {
    english = await AppLocalizations.delegate.load(const Locale('en'));
  });

  group('ux-16: what is wrong with it, and the press that fixes it', () {
    test('a hole is a boundary-edge row, and Fill is what closes it', () {
      final EditMesh mesh = _holed();
      final List<MeshIssue> before = MeshChecks(mesh).all();
      final MeshIssue hole = before.firstWhere(
        (MeshIssue it) => it.kind == MeshIssueKind.boundaryEdge,
      );

      // The acceptance this row states: the row counts the hole's own four
      // boundary edges, and the fix is one press.
      expect(hole.ids, hasLength(4));
      expect(fixToolFor(hole.kind), 'mesh.fillHoles');
      expect(fixLabelFor(english, hole.kind), 'Fill');

      // And the tool it names is a real one that closes it.
      final ModelCommand? fill = commandFor(
        'mesh.fillHoles',
        activeObject: null,
        editMesh: mesh,
      );
      expect(fill, isA<FillHoles>());
      mesh.beginStep();
      fillHoles(mesh);
      mesh.endStep();
      expect(
        MeshChecks(
          mesh,
        ).all().where((MeshIssue it) => it.kind == MeshIssueKind.boundaryEdge),
        isEmpty,
      );
    });

    test('an n-gon triangulates and a duplicate merges', () {
      // Mutation: one fix for every kind, or none. A row that counts
      // something and offers no way to act on it is a row people learn to
      // scroll past, which is what the status line's own sentence had
      // already become.
      expect(fixToolFor(MeshIssueKind.ngon), 'mesh.triangulate');
      expect(fixToolFor(MeshIssueKind.duplicateVertex), 'mesh.merge');
      expect(fixToolFor(MeshIssueKind.invertedShell), 'mesh.normals');
      // And the ones with no one-press answer say so rather than offering a
      // button that does something else.
      expect(fixToolFor(MeshIssueKind.nonManifoldVertex), isNull);
      expect(fixToolFor(MeshIssueKind.isolatedVertex), isNull);
    });

    testWidgets('a row selects what it names, at its own level', (
      WidgetTester tester,
    ) async {
      final List<MeshIssue> issues = MeshChecks(_holed()).all();
      final picked = <(ElementLevel, List<int>)>[];
      final fixed = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: modelerTheme(),
          home: Scaffold(
            body: MeshHealthPanel(
              issues: issues,
              onSelect: (ElementLevel level, List<int> ids) =>
                  picked.add((level, ids)),
              onFix: fixed.add,
            ),
          ),
        ),
      );

      final MeshIssue hole = issues.firstWhere(
        (MeshIssue it) => it.kind == MeshIssueKind.boundaryEdge,
      );
      await tester.tap(find.text(hole.message));
      await tester.pump();

      // Mutation: select at the mesh's own current level rather than the
      // issue's. A hole is edges and a person in vertex mode would be handed
      // four numbers that mean four different elements.
      expect(picked.single.$1, MeshIssueKind.boundaryEdge.level);
      expect(picked.single.$2, hasLength(4));

      await tester.tap(find.text('Fill'));
      await tester.pump();
      expect(fixed, <String>['mesh.fillHoles']);
    });

    testWidgets('a clean mesh says so rather than showing an empty list', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: modelerTheme(),
          home: Scaffold(
            body: MeshHealthPanel(
              issues: const <MeshIssue>[],
              onSelect: (_, _) {},
              onFix: (_) {},
            ),
          ),
        ),
      );

      expect(find.text('Nothing wrong with it'), findsOneWidget);
    });
  });

  group('ux-16: building topology for an import', () {
    ModelProject imported() => const ModelProject().added(
      (int id) => ModelObject(
        id: id,
        name: 'scan',
        geometry: ImportedGeometry(_unwelded()),
        transform: vm.Matrix4.identity(),
      ),
    );

    test('an unwelded import becomes a mesh whose corners are shared', () {
      final ModelHistory history = ModelHistory(imported());
      final int id = history.project.objects.single.id;

      expect(history.run(BuildTopology(id: id)), isNull);

      // The acceptance this row states, as far as the document goes: what
      // comes back is an editable mesh, and the welding actually happened —
      // six source corners over two triangles are four vertices.
      final Geometry built = history.project.objects.single.geometry;
      expect(built, isA<EditedGeometry>());
      expect((built as EditedGeometry).mesh.vertexCount, 4);
      expect(built.mesh.faceCount, 2);
    });

    test('and a mesh that already has topology is refused, not rebuilt', () {
      final ModelHistory history = ModelHistory(
        const ModelProject().added(
          (int id) => ModelObject(
            id: id,
            name: 'cube',
            geometry: EditedGeometry(EditMesh.cuboid()),
            transform: vm.Matrix4.identity(),
          ),
        ),
      );

      // Mutation: rebuild it anyway. Topology built a second time from a
      // mesh's own buffers throws away every edit that made it what it is —
      // the creases, the seams, the ids an agent quoted.
      expect(
        history.run(BuildTopology(id: history.project.objects.single.id)),
        contains('already has topology'),
      );
    });

    test('the weld survives the journal', () {
      const BuildTopology command = BuildTopology(id: 3, weld: 0.002);
      final ModelCommand? read = modelCommandFromJson(command.toJson());

      expect(read, isA<BuildTopology>());
      expect((read! as BuildTopology).weld, 0.002);
      // Absent means the import's own scale-aware default, which is what a
      // caller that did not choose one gets.
      expect(
        (modelCommandFromJson(const BuildTopology(id: 3).toJson())!
                as BuildTopology)
            .weld,
        isNull,
      );
    });
  });

  group('ux-16: mesh mode with nothing to edit', () {
    test('a shape offers the conversion, and names the key', () {
      final ({String said, String? button}) what = NoMeshBanner.says(
        ModelObject(
          id: 1,
          name: 'cylinder',
          geometry: ParametricGeometry(const ParametricCylinder()),
          transform: vm.Matrix4.identity(),
        ),
      );

      // Mutation: say nothing, which is what an empty mesh-mode viewport
      // did. No wireframe, no handles, nothing to click — the review found
      // people reading that as a broken window.
      expect(what.said, contains('cylinder'));
      expect(what.button, 'Convert to a mesh (B)');
    });

    test('an import offers the weld instead', () {
      final ({String said, String? button}) what = NoMeshBanner.says(
        ModelObject(
          id: 1,
          name: 'scan',
          geometry: ImportedGeometry(_unwelded()),
          transform: vm.Matrix4.identity(),
        ),
      );

      expect(what.button, 'Build topology');
    });

    test('and nothing selected is not a problem with the document', () {
      expect(NoMeshBanner.says(null).button, isNull);
      expect(NoMeshBanner.says(null).said, contains('Nothing is selected'));
    });

    test('a real mesh says nothing at all', () {
      expect(
        NoMeshBanner.says(
          ModelObject(
            id: 1,
            name: 'cube',
            geometry: EditedGeometry(EditMesh.cuboid()),
            transform: vm.Matrix4.identity(),
          ),
        ).said,
        isEmpty,
      );
    });
  });
}
