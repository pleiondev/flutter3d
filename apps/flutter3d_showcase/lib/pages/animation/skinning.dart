/// A banner bent by two joints: `Skeleton` moves it on the device, `SkinBlend`
/// mirrors the same arithmetic on the CPU so this page can check its own claim.
///
/// Quoted by `skinning.md` and shown whole in the Source tab.
library;

import 'dart:typed_data';

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_showcase/src/demo/demo.dart';
import 'package:vector_math/vector_math.dart';

final class SkinningDemo extends ShowcaseDemo {
  double bend = 0.5;

  static const double _depth = 2.4;
  static const double _maxAngle = 1.4; // a little under a right angle

  late final SceneNode _base;
  late final SceneNode _tip;
  late final Skeleton _skeleton;
  late final MeshData _cpuMesh;

  /// The vertex whose bind position sits halfway along the banner, where the
  /// blend of the two joints moves it the most — see `skinning.md`.
  late int _midVertex;

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
      name: 'flagpole',
    );
    // #endregion rig

    // #region weights
    _cpuMesh = const PlaneShape(
      width: 0.7,
      depth: _depth,
      depthSegments: 8,
    ).build().convertedTo(VertexLayout.skinned);
    _paintWeights(_cpuMesh);
    // #endregion weights

    // #region mesh
    final Material fabric = Material(
      name: 'banner',
      baseColor: Vector4(0.82, 0.24, 0.2, 1.0),
      roughness: 0.7,
      doubleSided: true,
    );
    final MeshNode banner = MeshNode(
      DeviceMesh.upload(context.device, _cpuMesh),
      fabric,
      name: 'banner',
    )..skeleton = _skeleton;
    // #endregion mesh

    return Scene()
      ..add(banner)
      ..add(
        LightNode(name: 'sun', intensity: 3.0)
          ..setLocalForward(Vector3(-0.3, -0.6, -0.7)),
      );
  }

  /// Every vertex leans on the base joint near `z = -depth/2` and on the tip
  /// joint near `z = +depth/2`, blending linearly between the two — the
  /// ordinary two-joint paint a rope or a flagpole gets.
  void _paintWeights(MeshData mesh) {
    final VertexLayout layout = mesh.layout;
    final int stride = layout.floatsPerVertex;
    final int positionAt = layout.floatOffsetOf(VertexLayout.position.name);
    final int jointsAt = layout.floatOffsetOf(VertexLayout.joints.name);
    final int weightsAt = layout.floatOffsetOf(VertexLayout.weights.name);
    final Float32List vertices = mesh.vertices;
    var closestToMiddle = double.infinity;

    for (var v = 0; v < mesh.vertexCount; v++) {
      final int at = v * stride;
      final double z = vertices[at + positionAt + 2];
      final double t = ((z + _depth / 2) / _depth).clamp(0.0, 1.0);
      vertices[at + jointsAt] = 0.0;
      vertices[at + jointsAt + 1] = 1.0;
      vertices[at + weightsAt] = 1.0 - t;
      vertices[at + weightsAt + 1] = t;

      if (z.abs() < closestToMiddle) {
        closestToMiddle = z.abs();
        _midVertex = v;
      }
    }
  }

  @override
  void update(DemoContext context, double dt) {
    // #region live
    _tip.setRotation(
      Quaternion.axisAngle(Vector3(1.0, 0.0, 0.0), bend * _maxAngle),
    );
    // #endregion live
  }

  @override
  List<DemoControl> controls(DemoContext context) => <DemoControl>[
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
    if (frame.skinnedDraws < 1) {
      throw StateError('the banner was not drawn through the skinned stage');
    }
    // The device already posed `_skeleton.matrices` for this frame; blending
    // them again on the CPU is `SkinBlend`'s own job, and the tip of the
    // banner should have left its bind position by as much as `bend` asked.
    final SkinBlend blend = SkinBlend(_cpuMesh);
    if (!blend.blend(_skeleton.matrices)) {
      throw StateError('SkinBlend saw no change from the bind pose');
    }
    final int stride = _cpuMesh.layout.floatsPerVertex;
    final int positionAt = _cpuMesh.layout.floatOffsetOf(
      VertexLayout.position.name,
    );
    final double skinnedY =
        blend.vertices[_midVertex * stride + positionAt + 1];
    if (skinnedY.abs() < 1e-3) {
      throw StateError('the banner did not follow the tip joint');
    }
  }
}
