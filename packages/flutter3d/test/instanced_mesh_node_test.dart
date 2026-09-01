/// One mesh drawn many times in one call.
///
///     flutter test test/instanced_mesh_node_test.dart
///
/// What is pinned here needs no device: the shape of the buffer the vertex
/// stage reads, the bounds a batch reports for culling, and the two things a
/// write has to invalidate. `flutter3d_cpu/test/instancing_test.dart` is
/// where the picture is held against the same field drawn one node at a time.
library;

import 'dart:math' as math;

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

CpuMesh _unitCube() =>
    CpuMesh(CuboidShape(size: Vector3(1.0, 1.0, 1.0)).build());

void main() {
  group('the buffer', () {
    test('holds three rows of the transform and a colour per instance', () {
      // The layout the vertex stage declares, byte for byte: sixteen floats,
      // rows first, colour last. A stage reading the wrong float reads a
      // translation as a colour and the batch draws black somewhere else.
      final node = InstancedMeshNode(_unitCube(), Material(), capacity: 2);
      final transform = Matrix4.translationValues(1.0, 2.0, 3.0)
        ..scaleByDouble(2.0, 2.0, 2.0, 1.0);

      node.addInstance(transform, color: Vector4(0.5, 0.25, 0.125, 1.0));

      final data = node.instanceData;
      expect(data.sublist(0, 4), <double>[2.0, 0.0, 0.0, 1.0]);
      expect(data.sublist(4, 8), <double>[0.0, 2.0, 0.0, 2.0]);
      expect(data.sublist(8, 12), <double>[0.0, 0.0, 2.0, 3.0]);
      expect(data.sublist(12, 16), <double>[0.5, 0.25, 0.125, 1.0]);
      expect(node.instanceBytes.lengthInBytes, InstancedMeshNode.strideInBytes);
    });

    test('reads a transform back as it was written', () {
      final node = InstancedMeshNode(_unitCube(), Material(), capacity: 1);
      final written = Matrix4.identity()
        ..rotateY(0.7)
        ..setTranslationRaw(4.0, -1.0, 2.5);
      node.addInstance(written);

      final read = Matrix4.zero();
      node.readTransform(0, read);

      for (var i = 0; i < 16; i++) {
        expect(read.storage[i], closeTo(written.storage[i], 1e-6));
      }
    });

    test('an unset instance is the identity with a white tint', () {
      // Not zeros: a matrix of zeros collapses the mesh to a point and a
      // colour of zeros draws it black, and both look like a missing draw.
      final node = InstancedMeshNode(_unitCube(), Material(), capacity: 3)
        ..count = 3;
      final read = Matrix4.zero();
      node.readTransform(2, read);

      expect(read, Matrix4.identity());
      expect(node.instanceData.sublist(44, 48), <double>[1.0, 1.0, 1.0, 1.0]);
    });

    test('refuses what it cannot hold', () {
      final node = InstancedMeshNode(_unitCube(), Material(), capacity: 1)
        ..addInstance(Matrix4.identity());

      expect(() => node.addInstance(Matrix4.identity()), throwsStateError);
      expect(() => node.count = 2, throwsRangeError);
      expect(() => node.setTransform(1, Matrix4.identity()), throwsRangeError);
      expect(
        () => InstancedMeshNode(_unitCube(), Material(), capacity: 0),
        throwsAssertionError,
      );
    });
  });

  group('the bounds', () {
    test('are the union of the placed instances', () {
      final node = InstancedMeshNode(_unitCube(), Material(), capacity: 4)
        ..addInstance(Matrix4.translationValues(10.0, 0.0, 0.0))
        ..addInstance(Matrix4.translationValues(-10.0, 0.0, 0.0))
        ..addInstance(
          Matrix4.translationValues(0.0, 5.0, 0.0)
            ..scaleByDouble(3.0, 3.0, 3.0, 1.0),
        );

      final bounds = node.localBounds;

      expect(bounds.min.x, closeTo(-10.5, 1e-6));
      expect(bounds.max.x, closeTo(10.5, 1e-6));
      expect(bounds.max.y, closeTo(5.0 + 1.5, 1e-6));
      expect(bounds.min.y, closeTo(-0.5, 1e-6));
    });

    test('rotate the corners rather than the extents', () {
      // A cube turned by 45 degrees about Y reaches sqrt(2) / 2 further along
      // X and Z than its extents say; taking the extents through the rotation
      // is only right for the axis-aligned case.
      final node = InstancedMeshNode(_unitCube(), Material(), capacity: 1)
        ..addInstance(Matrix4.rotationY(math.pi / 4));

      expect(node.localBounds.max.x, closeTo(math.sqrt(2.0) / 2.0, 1e-6));
    });

    test('follow a write, through the world bounds the renderer culls by', () {
      final scene = Scene();
      final node = InstancedMeshNode(_unitCube(), Material(), capacity: 1)
        ..addInstance(Matrix4.identity());
      scene.root.add(node);
      final before = node.worldBoundsRadius;

      node.setTransform(0, Matrix4.translationValues(100.0, 0.0, 0.0));

      expect(node.worldBounds.max.x, closeTo(100.5, 1e-6));
      expect(node.worldBoundsRadius, before, reason: 'one cube, moved');
      expect(node.worldBoundsCentre.x, closeTo(100.0, 1e-6));
    });

    test('an empty batch keeps the mesh\'s own bounds', () {
      final node = InstancedMeshNode(_unitCube(), Material(), capacity: 8);

      expect(node.localBounds.max, Vector3(0.5, 0.5, 0.5));
    });
  });

  test('a static caster that moves an instance asks for a re-bake', () {
    // The instances of a static batch are baked into the static shadow atlas,
    // and nothing else in a frame would notice one of them moving.
    final scene = Scene();
    final node = InstancedMeshNode(_unitCube(), Material(), capacity: 1)
      ..shadowIsStatic = true;
    scene.root.add(node);
    node.addInstance(Matrix4.identity());
    final generation = scene.staticShadowGeneration;

    node.setColor(0, Vector4(1.0, 0.0, 0.0, 1.0));

    expect(scene.staticShadowGeneration, greaterThan(generation));
  });
}
