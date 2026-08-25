import 'package:vector_math/vector_math.dart';

import '../geometry/geometry.dart';
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
  }) : transform = transform ?? Matrix4.identity();

  final DeviceMesh mesh;
  final Material material;
  final Matrix4 transform;
  final String? name;

  /// Index into [ModelAsset.skins], when this part is skinned.
  final int? skinIndex;

  final bool flipWinding;
}
