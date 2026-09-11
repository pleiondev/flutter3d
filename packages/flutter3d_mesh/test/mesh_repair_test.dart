/// `mesh-81n`'s own row, its `fillHoles` half: `EditMesh.makeConsistent`
/// already covers `flipShells` (see its own doc comment); `splitNonManifoldEdges`
/// and `fillHoles`'s own "fan" mode stay open — see `mesh_repair.dart`'s
/// own doc comment for why.
///
///     dart test test/mesh_repair_test.dart
library;

import 'package:flutter3d_mesh/flutter3d_mesh.dart';
import 'package:test/test.dart';

/// Wraps [body] in one journal step, the way every mutating call here needs.
void edit(EditMesh mesh, void Function() body) {
  mesh.beginStep();
  body();
  mesh.endStep();
}

void main() {
  group('fillHoles', () {
    test('a mesh with no boundary is left alone', () {
      final mesh = EditMesh.cuboid();
      expect(fillHoles(mesh), 0);
      expect(mesh.eulerCharacteristic, 2);
    });

    test(
      'a cube with one face removed closes back to a sphere, χ = 2 — '
      "mesh-81n's own acceptance line",
      () {
        final mesh = EditMesh.cuboid();
        expect(mesh.faceCount, 6);
        edit(mesh, () {
          mesh.deleteFace(0);
          mesh.repairVertexLinks();
        });
        expect(mesh.eulerCharacteristic, 1, reason: 'one open face: a disc, not a sphere');

        var closed = 0;
        edit(mesh, () => closed = fillHoles(mesh));
        expect(closed, 1);
        expect(mesh.eulerCharacteristic, 2);
      },
    );

    test('closing the hole welds every boundary edge, not just covers it', () {
      final mesh = EditMesh.cuboid();
      edit(mesh, () {
        mesh.deleteFace(0);
        mesh.repairVertexLinks();
      });
      expect(mesh.eulerCharacteristic, 1);

      var closed = 0;
      edit(mesh, () => closed = fillHoles(mesh));
      expect(closed, 1);
      expect(mesh.faceCount, 6);
      expect(mesh.eulerCharacteristic, 2);
      mesh.validate();

      // No half-edge of a live face is left without a live twin — the row's
      // own "closed" claim, checked directly rather than through χ alone.
      final issue = MeshChecks(mesh).boundaryEdges();
      expect(issue, isNull);
    });

    test('two separate holes are each closed with their own face', () {
      // Faces 0 ([4,5,6,7]) and 1 ([1,0,3,2]) share no vertex on
      // `EditMesh.cuboid()`'s own layout — opposite sides of the cube,
      // checked once here rather than assumed, since two adjacent holes
      // would merge into one and this test would stop meaning anything.
      final mesh = EditMesh.cuboid();
      expect(
        mesh.verticesOf(0).toSet().intersection(mesh.verticesOf(1).toSet()),
        isEmpty,
      );
      edit(mesh, () {
        mesh.deleteFace(0);
        mesh.deleteFace(1);
        mesh.repairVertexLinks();
      });
      expect(mesh.faceCount, 4);

      var closed = 0;
      edit(mesh, () => closed = fillHoles(mesh));
      expect(closed, 2);
      expect(mesh.faceCount, 6);
      expect(mesh.eulerCharacteristic, 2);
      mesh.validate();
    });

    test('the new face is wound outward, matching the rest of the cube', () {
      final mesh = EditMesh.cuboid();
      edit(mesh, () {
        mesh.deleteFace(0);
        mesh.repairVertexLinks();
      });
      edit(mesh, () => fillHoles(mesh));

      // A cube wound consistently outward has no closed island `makeConsistent`
      // needs to turn — if the new face came out backwards, this would flip it.
      var turned = false;
      edit(mesh, () => turned = mesh.makeConsistent());
      expect(turned, isFalse, reason: 'the new face should already point outward');
    });
  });

  group('boundaryChains', () {
    test('an untouched cube has none', () {
      expect(boundaryChains(EditMesh.cuboid()), isEmpty);
    });

    test('one removed face gives one chain, as many half-edges as sides', () {
      final mesh = EditMesh.cuboid();
      edit(mesh, () {
        mesh.deleteFace(0);
        mesh.repairVertexLinks();
      });
      final chains = boundaryChains(mesh);
      expect(chains, hasLength(1));
      expect(chains.single, hasLength(4));
    });
  });
}
