/// One mesh, one draw call, six different faces: `InstancedMeshNode
/// .setMorphWeights` gives each copy its own weights, read from a texture by
/// instance id instead of from a uniform every copy would share.
///
/// Quoted by `instanced_morphs.md` and shown whole in the Source tab.
library;

import 'dart:typed_data';

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_showcase/src/demo/demo.dart';
import 'package:vector_math/vector_math.dart';

final class InstancedMorphsDemo extends ShowcaseDemo {
  double spread = 1.0;

  static const int _count = 6;

  InstancedMeshNode? _faces;

  @override
  void configureView(DemoContext context) {
    context.orbit
      ..distance = 7.0
      ..pitch = 0.35;
  }

  @override
  Scene build(DemoContext context) {
    const int segments = 10;
    final MeshData flat = const PlaneShape(
      width: 0.9,
      depth: 0.9,
      widthSegments: segments,
      depthSegments: segments,
    ).build();
    final Float32List bump = Float32List(flat.vertexCount * 3);
    for (var v = 0; v < flat.vertexCount; v++) {
      final Vector3 p = flat.positionAt(v);
      final double r2 = p.x * p.x + p.y * p.y;
      bump[v * 3 + 2] = r2 < 0.16 ? (0.16 - r2) * 2.0 : 0.0;
    }
    final MeshData withBump = flat.withMorphTargets(<MorphTarget>[
      MorphTarget(vertexCount: flat.vertexCount, positions: bump, name: 'bump'),
    ]);
    final MorphTexture packed = MorphTexture.pack(withBump)!;
    final TextureHandle? deltaTexture = context.device.createTextureFromPixels(
      width: packed.width,
      height: packed.height,
      format: TextureFormat.r32g32b32a32Float,
      pixels: packed.bytes,
    );

    // #region batch
    final InstancedMeshNode faces = InstancedMeshNode(
      DeviceMesh.upload(context.device, withBump),
      Material(name: 'faces', baseColor: Vector4(0.8, 0.8, 0.85, 1.0)),
      capacity: _count,
      name: 'faces',
    );
    for (var i = 0; i < _count; i++) {
      faces.addInstance(
        Matrix4.translation(Vector3((i - (_count - 1) / 2) * 1.1, 0.0, 0.0)),
      );
    }
    if (deltaTexture != null) {
      faces.morph = MorphState(
        texture: deltaTexture,
        targetCount: packed.targetCount,
        reaches: packed.reaches,
      );
    }
    _faces = faces;
    // #endregion batch

    return Scene()
      ..add(faces)
      ..add(
        LightNode(name: 'sun', intensity: 3.0)
          ..setLocalForward(Vector3(-0.3, -0.6, -0.7)),
      );
  }

  @override
  void update(DemoContext context, double dt) {
    // #region live
    final InstancedMeshNode? faces = _faces;
    if (faces == null) return;
    for (var i = 0; i < _count; i++) {
      final double weight = (i / (_count - 1)) * spread;
      faces.setMorphWeights(i, <double>[weight]);
    }
    // #endregion live
  }

  @override
  List<DemoControl> controls(DemoContext context) => <DemoControl>[
    SliderControl(
      'Spread',
      min: 0,
      max: 1,
      value: () => spread,
      onChanged: (double v) => spread = v,
    ),
  ];

  @override
  void verify(Scene scene, FrameResult frame) {
    final InstancedMeshNode? faces = _faces;
    if (faces == null || !faces.hasInstanceMorphWeights) {
      throw StateError('no instance carries its own morph weights');
    }
    if (frame.instances < _count) {
      throw StateError('the batch did not draw all $_count instances');
    }
    final double first = faces.morphWeightsOf(0)[0];
    final double last = faces.morphWeightsOf(_count - 1)[0];
    if ((last - first).abs() < 1e-3) {
      throw StateError('every instance ended up with the same weight');
    }
  }
}
