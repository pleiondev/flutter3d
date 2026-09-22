/// The same bending banner `skinning` builds, with its skeleton drawn over
/// it: `DebugDrawOptions.skeletons` puts one octahedron a bone and one cross
/// a leaf joint on every skinned mesh in the scene.
///
/// Quoted by `skeleton_debug.md` and shown whole in the Source tab.
library;

import 'dart:typed_data';

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_showcase/src/demo/demo.dart';
import 'package:vector_math/vector_math.dart';

final class SkeletonDebugDemo extends ShowcaseDemo {
  bool showSkeleton = true;
  double bend = 0.6;

  static const double _depth = 2.4;

  late final SceneNode _base;
  late final SceneNode _tip;
  late final Skeleton _skeleton;

  @override
  void configureView(DemoContext context) {
    context.orbit
      ..distance = 4.0
      ..pitch = 0.15
      ..yaw = 0.5;
  }

  @override
  Scene build(DemoContext context) {
    // #region rig
    _base = SceneNode(name: 'base')..setPosition(0.0, 0.0, -_depth / 2);
    _tip = SceneNode(name: 'tip')..setPosition(0.0, 0.0, _depth);
    _base.add(_tip);

    final Matrix4 inverseBindBase = Matrix4.copy(_base.worldMatrix)..invert();
    final Matrix4 inverseBindTip = Matrix4.copy(_tip.worldMatrix)..invert();
    _skeleton = Skeleton(
      joints: <SceneNode>[_base, _tip],
      inverseBindMatrices: <Matrix4>[inverseBindBase, inverseBindTip],
      name: 'arm',
    );
    // #endregion rig

    final MeshData mesh = const PlaneShape(
      width: 0.7,
      depth: _depth,
      depthSegments: 8,
    ).build().convertedTo(VertexLayout.skinned);
    _paintWeights(mesh);

    final MeshNode banner = MeshNode(
      DeviceMesh.upload(context.device, mesh),
      Material(
        name: 'banner',
        baseColor: Vector4(0.5, 0.55, 0.6, 1.0),
        doubleSided: true,
      ),
      name: 'banner',
    )..skeleton = _skeleton;

    return Scene()
      ..add(banner)
      ..add(
        LightNode(name: 'sun', intensity: 3.0)
          ..setLocalForward(Vector3(-0.3, -0.6, -0.7)),
      );
  }

  void _paintWeights(MeshData mesh) {
    final VertexLayout layout = mesh.layout;
    final int stride = layout.floatsPerVertex;
    final int positionAt = layout.floatOffsetOf(VertexLayout.position.name);
    final int jointsAt = layout.floatOffsetOf(VertexLayout.joints.name);
    final int weightsAt = layout.floatOffsetOf(VertexLayout.weights.name);
    final Float32List vertices = mesh.vertices;
    for (var v = 0; v < mesh.vertexCount; v++) {
      final int at = v * stride;
      final double z = vertices[at + positionAt + 2];
      final double t = ((z + _depth / 2) / _depth).clamp(0.0, 1.0);
      vertices[at + jointsAt] = 0.0;
      vertices[at + jointsAt + 1] = 1.0;
      vertices[at + weightsAt] = 1.0 - t;
      vertices[at + weightsAt + 1] = t;
    }
  }

  @override
  void update(DemoContext context, double dt) {
    _tip.setRotation(Quaternion.axisAngle(Vector3(1.0, 0.0, 0.0), bend * 1.2));
  }

  // #region settings
  @override
  RenderSettings settings(DemoContext context) =>
      RenderSettings(debug: DebugDrawOptions(skeletons: showSkeleton));
  // #endregion settings

  @override
  List<DemoControl> controls(DemoContext context) => <DemoControl>[
    ToggleControl(
      'Show skeleton',
      value: () => showSkeleton,
      onChanged: (bool v) => showSkeleton = v,
    ),
    SliderControl(
      'Bend',
      min: 0,
      max: 1,
      value: () => bend,
      onChanged: (double v) => bend = v,
    ),
  ];

  @override
  void verify(Scene scene, FrameResult frame) {
    if (frame.debugLines < 1) {
      throw StateError('the skeleton overlay drew no lines');
    }
  }
}
