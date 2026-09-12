/// `DeviceMesh.overwriteVertices` — `pro-eng-01`'s own name for the mesh-side
/// half, over [FakeBackend] to check the byte arithmetic without a device.
///
///     flutter test test/device_mesh_overwrite_test.dart
library;

import 'dart:typed_data';

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_hardware/testing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

void main() {
  late FakeBackend device;
  late DeviceMesh mesh;
  late int stride;

  setUp(() {
    device = FakeBackend();
    mesh = DeviceMesh.upload(
      device,
      CuboidShape(size: Vector3.all(1.0)).build(),
    );
    stride = mesh.vertices.lengthInBytes ~/ mesh.vertexCount;
  });

  test('one vertex at the start writes at byte offset zero', () {
    mesh.overwriteVertices(device, 0, ByteData(stride));
    expect(device.overwrites, hasLength(1));
    expect(device.overwrites.single.offsetInBytes, 0);
    expect(device.overwrites.single.lengthInBytes, stride);
  });

  test('the byte offset scales with firstVertex, not with a vertex count', () {
    // Mutation: multiply by a vertex count instead of `firstVertex` — this
    // is the one test that tells the two apart, since `firstVertex: 1` and
    // `count: 1` are the same number.
    mesh.overwriteVertices(device, 3, ByteData(stride * 2));
    expect(device.overwrites.single.offsetInBytes, 3 * stride);
    expect(device.overwrites.single.lengthInBytes, stride * 2);
  });

  test('a length that is not a whole number of vertices is refused', () {
    expect(
      () => mesh.overwriteVertices(device, 0, ByteData(stride + 1)),
      throwsArgumentError,
    );
    expect(device.overwrites, isEmpty);
  });

  test('vertices past the end of the mesh are refused', () {
    expect(
      () => mesh.overwriteVertices(
        device,
        mesh.vertexCount - 1,
        ByteData(stride * 2),
      ),
      throwsArgumentError,
    );
    expect(device.overwrites, isEmpty);
  });

  test('a negative firstVertex is refused', () {
    expect(
      () => mesh.overwriteVertices(device, -1, ByteData(stride)),
      throwsArgumentError,
    );
    expect(device.overwrites, isEmpty);
  });

  /// One vertex's worth of bytes with [x], [y], [z] as its position — the
  /// rest of the stride stays zero, which no test here reads.
  ByteData vertexAt(double x, double y, double z) {
    final bytes = ByteData(stride);
    bytes
      ..setFloat32(0, x, Endian.host)
      ..setFloat32(4, y, Endian.host)
      ..setFloat32(8, z, Endian.host);
    return bytes;
  }

  group('bounds', () {
    test('grow to cover a vertex moved outside the mesh\'s own box', () {
      // The cuboid is size 1, so its own bounds run ±0.5 on every axis.
      final before = Aabb3.copy(mesh.bounds);
      expect(before.max.x, closeTo(0.5, 1e-9));

      mesh.overwriteVertices(device, 0, vertexAt(5.0, 0.0, 0.0));

      expect(mesh.bounds.max.x, closeTo(5.0, 1e-9));
      // Mutation: replace rather than union, and this drops to the single
      // moved vertex's own y/z instead of keeping the cuboid's.
      expect(mesh.bounds.max.y, closeTo(before.max.y, 1e-9));
      expect(mesh.bounds.min.x, closeTo(before.min.x, 1e-9));
    });

    test('do not shrink for a vertex moved inside the mesh\'s own box', () {
      final before = Aabb3.copy(mesh.bounds);
      mesh.overwriteVertices(device, 0, vertexAt(0.0, 0.0, 0.0));

      // Mutation: recompute from only the overwritten range instead of
      // unioning with what was already there, and this box collapses to a
      // single point at the origin.
      expect(mesh.bounds.min.x, closeTo(before.min.x, 1e-9));
      expect(mesh.bounds.max.x, closeTo(before.max.x, 1e-9));
    });
  });

  group('version', () {
    test('bumps once per call, regardless of how many vertices it touched', () {
      expect(mesh.version, 0);
      mesh.overwriteVertices(device, 0, vertexAt(0, 0, 0));
      expect(mesh.version, 1);
      mesh.overwriteVertices(device, 0, ByteData(stride * 4));
      expect(mesh.version, 2);
    });
  });
}
