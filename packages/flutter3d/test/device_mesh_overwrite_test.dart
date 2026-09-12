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
}
