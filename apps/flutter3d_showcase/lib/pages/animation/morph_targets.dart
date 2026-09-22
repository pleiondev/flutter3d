/// A grid that grows a bump: the deltas live in a `MorphTexture`, and
/// `MorphState` says how much of it to add right now.
///
/// Quoted by `morph_targets.md` and shown whole in the Source tab.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_showcase/src/demo/demo.dart';
import 'package:vector_math/vector_math.dart';

final class MorphTargetsDemo extends ShowcaseDemo {
  double weight = 0.7;

  MeshNode? _sheet;

  @override
  void configureView(DemoContext context) {
    context.orbit
      ..distance = 4.0
      ..pitch = 0.5;
  }

  @override
  Scene build(DemoContext context) {
    // #region target
    const int segments = 16;
    final MeshData flat = const PlaneShape(
      width: 2.0,
      depth: 2.0,
      widthSegments: segments,
      depthSegments: segments,
    ).build();
    final Float32List bump = Float32List(flat.vertexCount * 3);
    for (var v = 0; v < flat.vertexCount; v++) {
      final Vector3 p = flat.positionAt(v);
      final double falloff = _gaussian(p.x, p.z);
      bump[v * 3 + 1] = falloff * 0.9;
    }
    final MeshData withBump = flat.withMorphTargets(<MorphTarget>[
      MorphTarget(vertexCount: flat.vertexCount, positions: bump, name: 'bump'),
    ]);
    // #endregion target

    // #region texture
    final MorphTexture packed = MorphTexture.pack(withBump)!;
    final TextureHandle? deltaTexture = context.device.createTextureFromPixels(
      width: packed.width,
      height: packed.height,
      format: TextureFormat.r32g32b32a32Float,
      pixels: packed.bytes,
    );
    // #endregion texture

    final Material sheetMaterial = Material(
      name: 'sheet',
      baseColor: Vector4(0.3, 0.6, 0.85, 1.0),
      doubleSided: true,
    );
    final MeshNode sheet = MeshNode(
      DeviceMesh.upload(context.device, withBump),
      sheetMaterial,
      name: 'sheet',
    );
    if (deltaTexture != null) {
      // #region morph
      sheet.morph = MorphState(
        texture: deltaTexture,
        targetCount: packed.targetCount,
        reaches: packed.reaches,
      )..setWeights(<double>[weight]);
      // #endregion morph
    }
    _sheet = sheet;

    return Scene()
      ..add(sheet)
      ..add(
        LightNode(name: 'sun', intensity: 3.0)
          ..setLocalForward(Vector3(-0.4, -0.8, -0.3)),
      );
  }

  static double _gaussian(double x, double z) {
    final double r2 = x * x + z * z;
    return _exp(-r2 / 0.35);
  }

  static double _exp(double x) => x < -30 ? 0.0 : math.exp(x);

  @override
  void update(DemoContext context, double dt) {
    // #region live
    _sheet?.morph?.setWeights(<double>[weight]);
    // #endregion live
  }

  @override
  List<DemoControl> controls(DemoContext context) => <DemoControl>[
    SliderControl(
      'Weight',
      min: 0,
      max: 1,
      value: () => weight,
      onChanged: (double v) => weight = v,
    ),
  ];

  @override
  void verify(Scene scene, FrameResult frame) {
    final MorphState? morph = _sheet?.morph;
    if (morph == null) {
      throw StateError('the device would not take the morph delta texture');
    }
    if (morph.growth.max.y <= 0.0) {
      throw StateError('the weighted target did not grow the mesh upward');
    }
  }
}
