/// `mcp-09n`'s own composite verbs: `cleanup()`, `makeGameReady(profile)`,
/// `buildFrom(spec)` and `inspect()` — a recipe run through the whole
/// session, not one `ModelCommand` at a time.
///
///     dart test test/recipes_test.dart
library;

import 'dart:typed_data';

import 'package:flutter3d_core/formats.dart';
import 'package:flutter3d_mesh/flutter3d_mesh.dart';
import 'package:flutter3d_model_core/flutter3d_model_core.dart';
import 'package:flutter3d_model_mcp/flutter3d_model_mcp.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

List<Vector3> _boxPoints(Vector3 low, Vector3 high) => <Vector3>[
  Vector3(low.x, low.y, low.z),
  Vector3(high.x, low.y, low.z),
  Vector3(high.x, high.y, low.z),
  Vector3(low.x, high.y, low.z),
  Vector3(low.x, low.y, high.z),
  Vector3(high.x, low.y, high.z),
  Vector3(high.x, high.y, high.z),
  Vector3(low.x, high.y, high.z),
];

List<List<int>> _boxFaces(int base) => <List<int>>[
  <int>[base + 4, base + 5, base + 6, base + 7],
  <int>[base + 1, base + 0, base + 3, base + 2],
  <int>[base + 5, base + 1, base + 2, base + 6],
  <int>[base + 0, base + 4, base + 7, base + 3],
  <int>[base + 3, base + 7, base + 6, base + 2],
  <int>[base + 0, base + 1, base + 5, base + 4],
];

/// A cube with every face's own private copy of its four corners — no two
/// faces share a vertex index, the way a flat-shaded glTF export hands over
/// a box (one normal per corner needs one vertex per corner per face). 24
/// vertices, 6 faces; welding merges each corner's four copies down to the
/// cube's own eight, without touching the face count — `mcp-09n`'s own
/// acceptance scenario, and a case `mergeByDistance` does not also have to
/// drop a now-coincident face for, the way two boxes glued face to face
/// would (their shared wall doubles and `mergeByDistance` drops it, which
/// changes the face count for a different, real reason and would make a
/// poor fixture for this specific claim).
EditMesh _flatShadedCube() {
  final corners = _boxPoints(Vector3.zero(), Vector3(1, 1, 1));
  final points = <Vector3>[];
  final faces = <List<int>>[];
  for (final List<int> face in _boxFaces(0)) {
    final int base = points.length;
    points.addAll(<Vector3>[for (final int corner in face) corners[corner]]);
    faces.add(<int>[base, base + 1, base + 2, base + 3]);
  }
  return EditMesh.fromFaces(points, faces);
}

/// One triangle whose loop names a vertex twice — `MeshChecks.degenerateFaces`'s
/// own "pinched into a figure of eight" case, the simplest face with no area.
EditMesh _oneDegenerateTriangle() => EditMesh.fromFaces(
  <Vector3>[Vector3.zero(), Vector3(1, 0, 0), Vector3(0, 1, 0)],
  <List<int>>[
    <int>[0, 1, 0],
  ],
);

ModelSession _sessionWith(List<EditMesh> meshes) {
  var project = const ModelProject();
  for (final EditMesh mesh in meshes) {
    project = project.added(
      (int id) => ModelObject(
        id: id,
        name: 'mesh $id',
        geometry: EditedGeometry(mesh),
        transform: Matrix4.identity(),
      ),
    );
  }
  return ModelSession(ModelHistory(project));
}

void main() {
  group('cleanup', () {
    test('welds a flat-shaded cube without changing the face count', () {
      final session = _sessionWith(<EditMesh>[_flatShadedCube()]);
      final mesh =
          (session.project.objects.single.geometry as EditedGeometry).mesh;
      expect(mesh.vertexCount, 24);
      expect(mesh.faceCount, 6);

      final answer = session.cleanup();
      expect(answer.did, isTrue, reason: answer.says);

      final after =
          (session.project.objects.single.geometry as EditedGeometry).mesh;
      // Mutation: skip the weld step. Vertex count stays 24 and this fails.
      expect(after.vertexCount, 8);
      expect(after.faceCount, 6);
    });

    test('removes a degenerate face, and reports having done something', () {
      final session = _sessionWith(<EditMesh>[_oneDegenerateTriangle()]);
      final answer = session.cleanup();
      expect(answer.did, isTrue, reason: answer.says);
      final after =
          (session.project.objects.single.geometry as EditedGeometry).mesh;
      expect(after.faceCount, 0);
    });

    test('nothing to clean is reported, not silently accepted as done', () {
      final session = _sessionWith(<EditMesh>[EditMesh.cuboid()]);
      final answer = session.cleanup();
      expect(answer.did, isFalse);
      expect(answer.says, contains('nothing needed cleaning'));
      expect(session.history.canUndo, isFalse);
    });

    test('a project with no mesh objects is refused, not run', () {
      final session = ModelSession(ModelHistory(const ModelProject()));
      final answer = session.cleanup();
      expect(answer.did, isFalse);
      expect(answer.says, contains('nothing here has a mesh'));
    });

    test('every object cleaned in one call undoes in one step', () {
      final session = _sessionWith(<EditMesh>[
        _flatShadedCube(),
        _oneDegenerateTriangle(),
      ]);
      final answer = session.cleanup();
      expect(answer.did, isTrue, reason: answer.says);

      // Mutation: run each object's own commands outside a transaction. Two
      // objects touched would leave two steps on the stack instead of one.
      expect(session.history.steps, hasLength(1));

      expect(session.undo().did, isTrue);
      final restored =
          (session.project.objects.first.geometry as EditedGeometry).mesh;
      expect(restored.vertexCount, 24); // the flat-shaded cube, unwelded again
      final restoredOther =
          (session.project.objects.last.geometry as EditedGeometry).mesh;
      expect(restoredOther.faceCount, 1); // the degenerate triangle, back
    });
  });

  group('makeGameReady', () {
    Uint8List solidPng(int width, int height) {
      final rgba = Uint8List(width * height * 4);
      for (var i = 3; i < rgba.length; i += 4) {
        rgba[i] = 255;
      }
      return encodeCompressedPng(width, height, rgba);
    }

    test('triangulates and recalculates normals, one undo step', () {
      final session = _sessionWith(<EditMesh>[EditMesh.cuboid()]);
      final before =
          (session.project.objects.single.geometry as EditedGeometry).mesh;
      expect(before.faceCount, 6); // six quads

      final answer = session.makeGameReady('desktop');
      expect(answer.did, isTrue, reason: answer.says);
      expect(session.history.steps, hasLength(1));

      final after =
          (session.project.objects.single.geometry as EditedGeometry).mesh;
      // Mutation: skip the Triangulate call. Face count stays 6, all quads.
      expect(after.faceCount, 12);
    });

    test('fits images to the named budget without touching the project\'s '
        'own profile', () {
      var project = const ModelProject(
        profile: ProjectProfile(textures: TextureBudget.desktop),
      );
      // Bigger than mobile's own 1024px budget on both axes, and small
      // enough that desktop's 2048px would leave it untouched — the only
      // way this test can tell "fitted to mobile" from "not fitted at
      // all."
      project = project.copyWith(
        images: <EncodedImage>[EncodedImage(bytes: solidPng(2000, 1200))],
      );
      final session = ModelSession(ModelHistory(project));

      final answer = session.makeGameReady('mobile');
      expect(answer.did, isTrue, reason: answer.says);

      final dims = imageDimensions(session.project.images.single.bytes);
      // Mutation: pass no `budget` override to `FitTexturesToProfile` (or
      // the project's own profile's budget) — desktop's 2048px would leave
      // this image untouched.
      expect(
        dims,
        ImageDimensions(
          TextureBudget.mobile.maxSide,
          TextureBudget.mobile.maxSide,
        ),
      );
      expect(session.project.profile.textures, TextureBudget.desktop);
    });

    test('refuses a profile name it does not know', () {
      final session = ModelSession(ModelHistory(const ModelProject()));
      final answer = session.makeGameReady('potato');
      expect(answer.did, isFalse);
      expect(answer.says, contains('potato'));
    });

    test('nothing needed is reported, not silently accepted as done', () {
      final session = ModelSession(ModelHistory(const ModelProject()));
      final answer = session.makeGameReady('desktop');
      expect(answer.did, isFalse);
      expect(answer.says, contains('already game ready'));
      expect(session.history.canUndo, isFalse);
    });
  });

  group('buildFrom', () {
    test('builds a batch with a parent hierarchy in one call', () {
      final session = ModelSession(ModelHistory(const ModelProject()));
      final answer = session.buildFrom(<Map<String, Object?>>[
        <String, Object?>{'kind': 'box', 'name': 'trunk'},
        <String, Object?>{'kind': 'sphere', 'name': 'leaves', 'parent': 0},
      ]);
      expect(answer.did, isTrue, reason: answer.says);
      expect(session.project.objects, hasLength(2));
      final trunk = session.project.objects.firstWhere(
        (ModelObject o) => o.name == 'trunk',
      );
      final leaves = session.project.objects.firstWhere(
        (ModelObject o) => o.name == 'leaves',
      );
      expect(leaves.parent, trunk.id);
    });

    test('one undo step for the whole batch', () {
      final session = ModelSession(ModelHistory(const ModelProject()));
      session.buildFrom(<Map<String, Object?>>[
        <String, Object?>{'kind': 'box'},
        <String, Object?>{'kind': 'box'},
        <String, Object?>{'kind': 'box'},
      ]);
      // Mutation: run each addPrimitive outside a transaction. Three objects
      // built would leave three steps rather than one.
      expect(session.history.steps, hasLength(1));
      expect(session.undo().did, isTrue);
      expect(session.project.objects, isEmpty);
    });

    test('refuses an unknown kind before building anything', () {
      final session = ModelSession(ModelHistory(const ModelProject()));
      final answer = session.buildFrom(<Map<String, Object?>>[
        <String, Object?>{'kind': 'box'},
        <String, Object?>{'kind': 'teapot'},
      ]);
      expect(answer.did, isFalse);
      expect(answer.says, contains('teapot'));
      // Mutation: validate as it goes rather than up front. The first box
      // would already be sitting in the project when this is checked.
      expect(session.project.objects, isEmpty);
    });

    test('refuses a parent index this batch has not built yet', () {
      final session = ModelSession(ModelHistory(const ModelProject()));
      final answer = session.buildFrom(<Map<String, Object?>>[
        <String, Object?>{'kind': 'box', 'parent': 0},
      ]);
      expect(answer.did, isFalse);
      expect(answer.says, contains('parent'));
      expect(session.project.objects, isEmpty);
    });

    test('an empty batch is refused rather than a no-op success', () {
      final session = ModelSession(ModelHistory(const ModelProject()));
      final answer = session.buildFrom(const <Map<String, Object?>>[]);
      expect(answer.did, isFalse);
    });
  });

  group('inspect', () {
    test('reports object, vertex and face counts alongside check()', () {
      final session = _sessionWith(<EditMesh>[EditMesh.cuboid()]);
      final report = session.inspect();
      expect(report, contains('1 object'));
      expect(report, contains('vertices'));
      expect(report, contains('faces'));
      expect(report, contains(session.check()));
    });

    test('a project with nothing built says so, not zeroes with no '
        'context', () {
      final session = ModelSession(ModelHistory(const ModelProject()));
      final report = session.inspect();
      expect(report, contains('0 objects'));
    });
  });
}
