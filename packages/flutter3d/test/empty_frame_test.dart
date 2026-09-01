/// Why a frame drew nothing.
///
///     flutter test test/empty_frame_test.dart
///
/// A black viewport has several causes that look identical, and the picture can
/// name none of them. These pin the sentence each one produces.
library;

import 'dart:typed_data';

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

/// A cube, which is a mesh with indices. The one case that needs geometry
/// *without* them builds it directly.
CpuMesh _cube() => CpuMesh(CuboidShape(size: Vector3(1.0, 1.0, 1.0)).build());

/// Geometry that holds vertices and no triangles, which is what an asset that
/// failed to upload leaves behind.
CpuMesh _empty() {
  final cube = CuboidShape(size: Vector3(1.0, 1.0, 1.0)).build();
  return CpuMesh(
    MeshData(
      layout: cube.layout,
      vertices: cube.vertices,
      indices: Uint32List(0),
    ),
  );
}

void main() {
  late Scene scene;
  late RenderView view;

  setUp(() {
    scene = Scene();
    final camera = CameraNode();
    scene.root.add(camera);
    view = RenderView(camera: camera);
  });

  test('no views at all', () {
    expect(
      describeEmptyFrame(scene, const <RenderView>[]),
      contains('no views'),
    );
  });

  test('an empty scene names the registry, not the camera', () {
    // The mistake behind this one is a node built and never attached, and it
    // looks exactly like a camera pointing the wrong way.
    final why = describeEmptyFrame(scene, <RenderView>[view]);

    expect(why, contains('no meshes'));
    expect(why, contains('attached'));
  });

  test('every mesh hidden says visibility is inherited', () {
    // Because it is: one invisible ancestor hides a subtree whose own nodes
    // all report themselves visible, which is the version of this that costs
    // an afternoon.
    final parent = SceneNode()..visible = false;
    scene.root.add(parent);
    parent.add(MeshNode(_cube(), Material()));

    final why = describeEmptyFrame(scene, <RenderView>[view]);

    expect(why, contains('hidden'));
    expect(why, contains('inherited'));
  });

  test('geometry with no indices is its own case', () {
    scene.root.add(MeshNode(_empty(), Material()));

    expect(
      describeEmptyFrame(scene, <RenderView>[view]),
      contains('empty geometry'),
    );
  });

  test('a layer mask that matches nothing reports both masks', () {
    // The numbers are what makes it fixable: "no mask matches" leaves the
    // reader to go and find both of them.
    scene.root.add(MeshNode(_cube(), Material())..layerMask = 0x4);
    view.layerMask = 0x1;

    final why = describeEmptyFrame(scene, <RenderView>[view]);

    expect(why, contains('layer mask'));
    expect(why, contains('0x4'));
    expect(why, contains('0x1'));
  });

  test('a viewport of zero area throws before a frame can report it', () {
    // Which is why `describeEmptyFrame` has no case for it: the constructor
    // already refuses, and refusing where the value is written beats
    // explaining a frame later.
    expect(
      () => ViewportRect(0.0, 0.0, 0.0, 1.0),
      throwsA(isA<AssertionError>()),
    );
  });

  test('everything else is culling, stated as the elimination it is', () {
    // Deliberately not re-derived here: repeating the frustum test would be a
    // second implementation of culling, and its disagreement with the first is
    // the bug it would be reporting.
    scene.root.add(MeshNode(_cube(), Material()));

    final why = describeEmptyFrame(scene, <RenderView>[view]);

    expect(why, contains('frustum'));
    expect(why, contains('1 visible meshes'));
  });
}
