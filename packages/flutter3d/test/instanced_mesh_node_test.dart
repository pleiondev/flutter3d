/// One mesh drawn many times in one call.
///
///     flutter test test/instanced_mesh_node_test.dart
///
/// What is pinned here needs no device: the shape of the buffer the vertex
/// stage reads, the bounds a batch reports for culling, and the two things a
/// write has to invalidate. `flutter3d/test/instancing_test.dart` is
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
      final node = InstancedMeshNode(
        _unitCube(),
        RenderMaterial(),
        capacity: 2,
      );
      final transform = Matrix4.translationValues(1.0, 2.0, 3.0)
        ..scaleByDouble(2.0, 2.0, 2.0, 1.0);

      node.addInstance(transform, color: LinearColor(0.5, 0.25, 0.125, 1.0));

      final data = node.instanceData;
      expect(data.sublist(0, 4), <double>[2.0, 0.0, 0.0, 1.0]);
      expect(data.sublist(4, 8), <double>[0.0, 2.0, 0.0, 2.0]);
      expect(data.sublist(8, 12), <double>[0.0, 0.0, 2.0, 3.0]);
      expect(data.sublist(12, 16), <double>[0.5, 0.25, 0.125, 1.0]);
      expect(node.instanceBytes.lengthInBytes, InstancedMeshNode.strideInBytes);
    });

    test('reads a transform back as it was written', () {
      final node = InstancedMeshNode(
        _unitCube(),
        RenderMaterial(),
        capacity: 1,
      );
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
      final node = InstancedMeshNode(_unitCube(), RenderMaterial(), capacity: 3)
        ..count = 3;
      final read = Matrix4.zero();
      node.readTransform(2, read);

      expect(read, Matrix4.identity());
      const at = 2 * InstancedMeshNode.floatsPerInstance;
      expect(node.instanceData.sublist(at + 12, at + 16), <double>[
        1.0,
        1.0,
        1.0,
        1.0,
      ]);
      expect(node.instanceData.sublist(at + 16, at + 20), <double>[
        0.0,
        0.0,
        0.0,
        0.0,
      ], reason: 'an instance\'s own numbers start at nought');
    });

    test('holds four numbers of the game\'s own after the colour — P8', () {
      // What `i_data` reads, at byte 64 of the record: a material's
      // `instance`. Mutation: write them at the colour's offset.
      final node = InstancedMeshNode(
        _unitCube(),
        RenderMaterial(),
        capacity: 2,
      );
      node.addInstance(
        Matrix4.identity(),
        color: LinearColor(0.5, 0.5, 0.5, 1.0),
        data: Vector4(0.1, 0.2, 0.3, 0.4),
      );
      expect(node.instanceData.sublist(12, 16), <double>[0.5, 0.5, 0.5, 1.0]);
      final data = node.instanceData.sublist(16, 20);
      for (final (i, value) in <double>[0.1, 0.2, 0.3, 0.4].indexed) {
        expect(data[i], closeTo(value, 1e-6));
      }
      final read = Vector4.zero();
      node.readInstanceData(0, read);
      expect(read.y, closeTo(0.2, 1e-6));
      expect(InstancedMeshNode.strideInBytes, 80);
    });

    test('a slot taken again starts from nought, and a released one carries '
        'its numbers to where it moved', () {
      final node = InstancedMeshNode(
        _unitCube(),
        RenderMaterial(),
        capacity: 2,
      );
      final first = node.acquire(data: Vector4(1.0, 0.0, 0.0, 0.0));
      final second = node.acquire(data: Vector4(0.0, 2.0, 0.0, 0.0));
      node.release(first);
      final read = Vector4.zero();
      node.readInstanceData(second.index, read);
      expect(read.y, 2.0, reason: 'the moved slot kept its numbers');
      final third = node.acquire();
      node.readInstanceData(third.index, read);
      expect(read, Vector4.zero(), reason: 'a fresh slot starts at nought');
    });

    test('refuses what it cannot hold', () {
      final node = InstancedMeshNode(_unitCube(), RenderMaterial(), capacity: 1)
        ..addInstance(Matrix4.identity());

      expect(() => node.addInstance(Matrix4.identity()), throwsStateError);
      expect(() => node.count = 2, throwsRangeError);
      expect(() => node.setTransform(1, Matrix4.identity()), throwsRangeError);
      expect(
        () => InstancedMeshNode(_unitCube(), RenderMaterial(), capacity: 0),
        throwsAssertionError,
      );
    });
  });

  group('the bounds', () {
    test('are the union of the placed instances', () {
      final node = InstancedMeshNode(_unitCube(), RenderMaterial(), capacity: 4)
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
      final node = InstancedMeshNode(_unitCube(), RenderMaterial(), capacity: 1)
        ..addInstance(Matrix4.rotationY(math.pi / 4));

      expect(node.localBounds.max.x, closeTo(math.sqrt(2.0) / 2.0, 1e-6));
    });

    test('follow a write, through the world bounds the renderer culls by', () {
      final scene = Scene();
      final node = InstancedMeshNode(_unitCube(), RenderMaterial(), capacity: 1)
        ..addInstance(Matrix4.identity());
      scene.root.add(node);
      final before = node.worldBoundsRadius;

      node.setTransform(0, Matrix4.translationValues(100.0, 0.0, 0.0));

      expect(node.worldBounds.max.x, closeTo(100.5, 1e-6));
      expect(node.worldBoundsRadius, before, reason: 'one cube, moved');
      expect(node.worldBoundsCenter.x, closeTo(100.0, 1e-6));
    });

    test('an empty batch keeps the mesh\'s own bounds', () {
      final node = InstancedMeshNode(
        _unitCube(),
        RenderMaterial(),
        capacity: 8,
      );

      expect(node.localBounds.max, Vector3(0.5, 0.5, 0.5));
    });
  });

  test('a static caster that moves an instance asks for a re-bake', () {
    // The instances of a static batch are baked into the static shadow atlas,
    // and nothing else in a frame would notice one of them moving.
    final scene = Scene();
    final node = InstancedMeshNode(_unitCube(), RenderMaterial(), capacity: 1)
      ..shadowIsStatic = true;
    scene.root.add(node);
    node.addInstance(Matrix4.identity());
    final generation = scene.staticShadowGeneration;

    node.setColor(0, LinearColor(1.0, 0.0, 0.0, 1.0));

    expect(scene.staticShadowGeneration, greaterThan(generation));
  });
  group('slots by handle', () {
    Vector3 placeOf(InstancedMeshNode node, int index) {
      final m = Matrix4.zero();
      node.readTransform(index, m);
      return m.getTranslation();
    }

    test('a release in the middle moves the last into the hole, and its '
        'handle follows', () {
      // Three shots in the air; the first hits something. The third still
      // has to be drawn, and its owner still has to find it.
      final node = InstancedMeshNode(
        _unitCube(),
        RenderMaterial(),
        capacity: 4,
      );
      final first = node.acquire(
        transform: Matrix4.translationValues(1.0, 0.0, 0.0),
      );
      node.acquire(transform: Matrix4.translationValues(2.0, 0.0, 0.0));
      final third = node.acquire(
        transform: Matrix4.translationValues(3.0, 0.0, 0.0),
        color: LinearColor(1.0, 0.0, 0.0, 1.0),
      );

      node.release(first);

      expect(node.count, 2);
      expect(first.isLive, isFalse);
      expect(third.index, 0);
      expect(placeOf(node, 0).x, 3.0);
      expect(node.instanceData[12], 1.0);
      expect(node.instanceData[13], 0.0, reason: 'the colour moved too');
      third.setTransform(Matrix4.translationValues(4.0, 0.0, 0.0));
      expect(placeOf(node, 0).x, 4.0);
      expect(() => node.release(first), throwsStateError);
    });

    test('a full batch grows rather than refusing', () {
      final node = InstancedMeshNode(
        _unitCube(),
        RenderMaterial(),
        capacity: 1,
      );
      final handles = [for (var i = 0; i < 5; i++) node.acquire()];
      expect(node.count, 5);
      expect(node.capacity, greaterThanOrEqualTo(5));
      expect(handles.map((h) => h.index), <int>[0, 1, 2, 3, 4]);
    });

    test('clear lets go of every handle', () {
      final node = InstancedMeshNode(
        _unitCube(),
        RenderMaterial(),
        capacity: 2,
      );
      final handle = node.acquire();
      node.clear();
      expect(handle.isLive, isFalse);
      expect(node.acquire().index, 0);
    });
  });
}
