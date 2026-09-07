import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:vector_math/vector_math.dart';

import '../geometry/device_mesh.dart';
import '../render/material.dart';

/// One drawable piece of a model: geometry, appearance, and where it sits
/// relative to the model's own origin.
final class ModelPart {
  ModelPart({
    required this.mesh,
    required this.material,
    Matrix4? transform,
    this.name,
    this.skinIndex,
    this.flipWinding = false,
    this.morphTexture,
    this.morphTargetCount = 0,
    List<double>? morphWeights,
  }) : transform = transform ?? Matrix4.identity(),
       morphWeights = morphWeights ?? const <double>[];

  final DeviceMesh mesh;
  final Material material;
  final Matrix4 transform;
  final String? name;

  /// Index into [ModelAsset.skins], when this part is skinned.
  final int? skinIndex;

  final bool flipWinding;

  /// This surface's morph deltas, uploaded once and shared by every instance.
  ///
  /// Null for almost every part. The *weights* are not here: they belong to the
  /// node an instance created, so that two copies of one model can wear
  /// different expressions from one upload — see `MorphState`.
  final TextureHandle? morphTexture;

  /// How many targets [morphTexture] holds, which can be fewer than the file
  /// carried when it named more shapes than the shader blends.
  final int morphTargetCount;

  /// The expression this part starts in, before anything animates it.
  final List<double> morphWeights;
}
