/// The layers a mesh carries besides its shape.
///
/// Three claims are worth the file on their own, and each has a mutation named
/// beside it: a layer nobody wrote does not exist and reads as neutral, an edge
/// flag reaches both halves of its edge, and a layer that arrives in the middle
/// of a session still undoes in step with everything else.
library;

import 'package:flutter3d_geometry/flutter3d_geometry.dart';
import 'package:flutter3d_mesh/flutter3d_mesh.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

void main() {
  group('a layer nobody wrote', () {
    test('does not exist, and reads as the neutral value', () {
      final cube = EditMesh.cuboid();

      expect(cube.hasLayer(MeshDomain.corner, MeshAttribute.uv0), isFalse);
      expect(cube.hasLayer(MeshDomain.corner, MeshAttribute.colour), isFalse);
      expect(cube.hasLayer(MeshDomain.vertex, MeshAttribute.weights), isFalse);

      expect(cube.uvOf(0), Vector2.zero());
      // White rather than black: a corner nobody painted must not multiply the
      // surface to nothing.
      expect(cube.colourOf(0), kNeutralColor);
      // All of the first joint, which is what an unskinned vertex means.
      expect(cube.skinOf(0).weights, kNeutralWeights);
      expect(cube.creaseOf(0), 0);
      expect(cube.edgeHas(0, EdgeFlags.sharp), isFalse);
      expect(cube.materialSlotOf(0), 0);
    });

    test('is created by the first write and not by a read', () {
      final cube = EditMesh.cuboid()
        ..uvOf(0)
        ..colourOf(0)
        ..skinOf(0);
      expect(cube.hasLayer(MeshDomain.corner, MeshAttribute.uv0), isFalse);

      cube
        ..beginStep()
        ..setUv(0, Vector2(0.25, 0.5));
      cube.endStep();

      expect(cube.hasLayer(MeshDomain.corner, MeshAttribute.uv0), isTrue);
      expect(cube.uvOf(0), Vector2(0.25, 0.5));
      // And only that one: the other layers are still absent.
      expect(cube.hasLayer(MeshDomain.corner, MeshAttribute.colour), isFalse);
    });

    test('a corner copied from a bare mesh creates nothing', () {
      final cube = EditMesh.cuboid();

      cube
        ..beginStep()
        ..setCorner(1, cube.cornerOf(0));
      cube.endStep();

      // Mutation: write unconditionally in `setCorner` and both layers appear,
      // full of the neutral values the copy had just read — a megabyte of
      // "white" and "the origin" on every mesh an extrusion touches.
      expect(cube.hasLayer(MeshDomain.corner, MeshAttribute.uv0), isFalse);
      expect(cube.hasLayer(MeshDomain.corner, MeshAttribute.colour), isFalse);
    });
  });

  group('where an attribute lives', () {
    test('two corners at one vertex hold different texture coordinates', () {
      final cube = EditMesh.cuboid();
      // Two half-edges leaving the same vertex, on different faces — which is
      // what a seam is.
      final first = cube.outgoingOf(0);
      var second = -1;
      for (var half = 0; half < cube.halfEdgeSlotCount; half++) {
        if (half != first && cube.originOf(half) == 0) {
          second = half;
          break;
        }
      }
      expect(second, isNot(-1));

      cube
        ..beginStep()
        ..setUv(first, Vector2(0, 0))
        ..setUv(second, Vector2(1, 0));
      cube.endStep();

      // The claim the corner domain exists for: a per-vertex UV could not hold
      // both of these, and a mesh that cannot hold both cannot have a seam.
      expect(cube.uvOf(first), Vector2(0, 0));
      expect(cube.uvOf(second), Vector2(1, 0));
    });

    test('an edge flag reaches both halves of the edge', () {
      final cube = EditMesh.cuboid();
      final half = 0;
      final twin = cube.twinOf(half);
      expect(twin, isNot(EditMesh.none));

      cube
        ..beginStep()
        ..setEdgeFlag(half, EdgeFlags.sharp, on: true);
      cube.endStep();

      // Mutation: write only the half-edge given and this is false — a crease
      // that exists when the mesh is walked from one side and not from the
      // other, which is a bug nobody reproduces on the first try.
      expect(cube.edgeHas(twin, EdgeFlags.sharp), isTrue);
      expect(cube.edgeHas(half, EdgeFlags.sharp), isTrue);
    });

    test('sharp and seam are separate bits of one layer', () {
      final cube = EditMesh.cuboid();

      cube
        ..beginStep()
        ..setEdgeFlag(0, EdgeFlags.sharp, on: true)
        ..setEdgeFlag(0, EdgeFlags.seam, on: true)
        ..setEdgeFlag(0, EdgeFlags.sharp, on: false);
      cube.endStep();

      // Clearing one must not clear the other: a cylinder's seam is not a hard
      // edge, and a box's hard edges are not all seams.
      expect(cube.edgeHas(0, EdgeFlags.sharp), isFalse);
      expect(cube.edgeHas(0, EdgeFlags.seam), isTrue);
    });

    test('a material slot and a shading flag are per face', () {
      final cube = EditMesh.cuboid();

      cube
        ..beginStep()
        ..setMaterialSlot(2, 3)
        ..setFaceFlag(2, FaceFlags.smooth, on: true);
      cube.endStep();

      expect(cube.materialSlotOf(2), 3);
      expect(cube.faceHas(2, FaceFlags.smooth), isTrue);
      expect(cube.materialSlotOf(1), 0);
      expect(cube.faceHas(1, FaceFlags.smooth), isFalse);
    });
  });

  group('a layer that arrives late', () {
    test('undoes in step with the arrays that were always there', () {
      final cube = EditMesh.cuboid();

      // Three ordinary edits first, so the journal is three deep before the UV
      // layer exists at all.
      for (var i = 0; i < 3; i++) {
        cube
          ..beginStep()
          ..moveVertex(i, Vector3(i.toDouble(), 0, 0));
        cube.endStep();
      }
      expect(cube.undoDepth, 3);

      cube
        ..beginStep()
        ..setUv(0, Vector2(0.5, 0.5));
      cube.endStep();
      expect(cube.undoDepth, 4);

      expect(cube.undo(), isTrue);
      expect(cube.uvOf(0), Vector2.zero());
      expect(cube.positionOf(2), Vector3(2, 0, 0));

      expect(cube.undo(), isTrue);
      expect(cube.positionOf(2), isNot(Vector3(2, 0, 0)));
    });

    test('and redoes in step, which is where a short journal shows', () {
      final cube = EditMesh.cuboid();
      for (var i = 0; i < 3; i++) {
        cube
          ..beginStep()
          ..moveVertex(i, Vector3(i.toDouble(), 0, 0));
        cube.endStep();
      }
      cube
        ..beginStep()
        ..setUv(0, Vector2(0.5, 0.5));
      cube.endStep();

      // All the way back, then all the way forward.
      while (cube.undo()) {}
      expect(cube.uvOf(0), Vector2.zero());

      // **The first redo must not bring the UV back.** It is the fourth edit,
      // and three come before it. Mutation: skip `padSteps` when a layer is
      // created, and the layer holds one step where everything else holds four
      // — so its single step is replayed by the *first* redo and the texture
      // coordinate appears three edits before it was ever set. Undo alone does
      // not catch this, because the missing steps are the oldest ones and undo
      // reaches them last; redo starts at exactly the end that is short.
      expect(cube.redo(), isTrue);
      expect(
        cube.uvOf(0),
        Vector2.zero(),
        reason: 'the UV came back too early',
      );

      expect(cube.redo(), isTrue);
      expect(cube.uvOf(0), Vector2.zero());
      expect(cube.redo(), isTrue);
      expect(cube.uvOf(0), Vector2.zero());

      expect(cube.redo(), isTrue);
      expect(cube.uvOf(0), Vector2(0.5, 0.5));
    });

    test('a layer created inside a step is undone with that step', () {
      final cube = EditMesh.cuboid();

      cube
        ..beginStep()
        ..moveVertex(0, Vector3(9, 9, 9))
        ..setColour(0, Vector4(1, 0, 0, 1));
      cube.endStep();

      cube.undo();

      expect(cube.colourOf(0), kNeutralColor);
      expect(cube.positionOf(0), isNot(Vector3(9, 9, 9)));
    });
  });

  group('what an operation inherits', () {
    test('a corner between two is the average of both', () {
      final a = CornerAttributes(
        uv: Vector2(0, 0),
        colour: Vector4(1, 0, 0, 1),
      );
      final b = CornerAttributes(
        uv: Vector2(1, 1),
        colour: Vector4(0, 1, 0, 1),
      );

      final middle = CornerAttributes.lerp(a, b, 0.5);

      expect(middle.uv, Vector2(0.5, 0.5));
      expect(middle.colour, Vector4(0.5, 0.5, 0, 1));
    });

    test('a split between two skins keeps four joints and sums to one', () {
      // Different joints on each side, which is the case that makes this more
      // than a lerp: four plus four is eight, and a shader holds four.
      final a = VertexAttributes(
        joints: Vector4(0, 1, 2, 3),
        weights: Vector4(0.4, 0.3, 0.2, 0.1),
      );
      final b = VertexAttributes(
        joints: Vector4(4, 5, 6, 7),
        weights: Vector4(0.4, 0.3, 0.2, 0.1),
      );

      final middle = VertexAttributes.lerp(a, b, 0.5);

      final total =
          middle.weights.x +
          middle.weights.y +
          middle.weights.z +
          middle.weights.w;
      // Mutation: keep the four strongest and skip the renormalisation, and
      // this is 0.7 — a vertex that follows its bones seven tenths of the way
      // and shrinks towards the origin for the rest.
      expect(total, closeTo(1.0, 1e-6));

      // The four kept are the four that pulled hardest: 0.2 apiece from joints
      // 0 and 4, then 0.15 from 1 and 5.
      final kept = <int>{for (var i = 0; i < 4; i++) middle.joints[i].round()};
      expect(kept, <int>{0, 4, 1, 5});
    });

    test('the same joint on both sides is added rather than kept twice', () {
      final a = VertexAttributes(
        joints: Vector4(3, 0, 0, 0),
        weights: Vector4(1, 0, 0, 0),
      );
      final b = VertexAttributes(
        joints: Vector4(3, 0, 0, 0),
        weights: Vector4(1, 0, 0, 0),
      );

      final middle = VertexAttributes.lerp(a, b, 0.5);

      expect(middle.joints.x, 3);
      expect(middle.weights.x, closeTo(1.0, 1e-6));
      expect(middle.weights.y, 0);
    });
  });

  group('handing the layers to the engine', () {
    test('texture coordinates reach the drawable mesh', () {
      final cube = EditMesh.cuboid();
      cube.beginStep();
      var half = cube.halfEdgeOf(0);
      final corners = <int>[];
      cube.forEachHalfEdge(0, corners.add);
      for (var i = 0; i < corners.length; i++) {
        cube.setUv(corners[i], Vector2(i.isEven ? 0 : 1, i < 2 ? 0 : 1));
      }
      cube.endStep();
      half = corners.first;

      final mesh = cube.toMeshData();
      final offset = mesh.layout.floatOffsetOf(VertexLayout.texcoord.name);
      final stride = mesh.layout.floatsPerVertex;

      // The first face's first corner is the first vertex the conversion
      // writes, and it carries the UV that was set on that half-edge.
      expect(mesh.vertices[offset], cube.uvOf(half).x);
      expect(mesh.vertices[offset + 1], cube.uvOf(half).y);

      // Somewhere in the mesh there is a corner at (1, 1) — mutation: write
      // `Vector2.zero()` in `toMeshData` the way the spike did, and every one
      // of these is the origin.
      var found = false;
      for (var v = 0; v < mesh.vertexCount; v++) {
        final u = mesh.vertices[v * stride + offset];
        final w = mesh.vertices[v * stride + offset + 1];
        if (u == 1 && w == 1) found = true;
      }
      expect(found, isTrue);
    });

    test('a mesh with no colour layer still draws white', () {
      final cube = EditMesh.cuboid();

      final mesh = cube.toMeshData();
      final offset = mesh.layout.floatOffsetOf(VertexLayout.color.name);

      expect(mesh.vertices[offset], 1.0);
      expect(mesh.vertices[offset + 3], 1.0);
    });
  });
}
