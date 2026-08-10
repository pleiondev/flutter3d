import 'package:flutter3d/flutter3d.dart';

/// Something the demo can display: a procedural shape or a model file.
sealed class SceneSource {
  const SceneSource(this.label);

  /// Shown in the UI and used as the cache key.
  final String label;

  Future<ModelAsset> load({
    required TextureHandle fallbackAlbedo,
    required TextureHandle checkerAlbedo,
  });
}

/// A shape generated in code.
///
/// Holds a [Shape] rather than a closure, which is the payoff of shapes being
/// values: the source can report the shape's own name, and a caller can inspect
/// or reparameterize it instead of only being able to invoke it.
final class ProceduralSource extends SceneSource {
  const ProceduralSource(super.label, this.shape);

  final Shape shape;

  @override
  Future<ModelAsset> load({
    required TextureHandle fallbackAlbedo,
    required TextureHandle checkerAlbedo,
  }) async {
    // Generation is fast enough to stay on the UI isolate: a 33k-vertex sphere
    // builds in 0.9 ms, and shipping the result to another isolate would cost
    // more in copying than the work itself.
    return ModelAsset.fromMesh(
      shape.build(),
      name: label,
      // Checkerboard rather than flat white: a procedural shape with no material
      // is exactly where UV mistakes hide.
      material: Material(albedo: checkerAlbedo, roughness: 0.35),
    );
  }
}

/// A model file from the asset bundle, decoded on a background isolate.
///
/// One class for glTF, GLB and OBJ: the format is detected from the file, and both
/// decoders produce the same [ModelDocument], so there is nothing format-specific
/// left at this level.
final class ModelFileSource extends SceneSource {
  const ModelFileSource(super.label, this.assetPath, {this.objNormals});

  final String assetPath;

  /// Only consulted for OBJ, which has no rule about missing normals.
  final ObjNormals? objNormals;

  @override
  Future<ModelAsset> load({
    required TextureHandle fallbackAlbedo,
    required TextureHandle checkerAlbedo,
  }) async {
    final document = await decodeModelInIsolate(
      ModelLoadRequest(
        source: BundleAssetSource(assetPath),
        objNormals: objNormals ?? ObjNormals.smooth,
      ),
    );

    // Uploading has to happen back on this isolate: GPU resources belong to the
    // context that created them.
    return ModelAsset.fromDocument(
      document,
      fallbackAlbedo: fallbackAlbedo,
      name: label,
    );
  }
}
