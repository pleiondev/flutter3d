import 'package:vector_math/vector_math.dart';

import '../model_document.dart';

/// A material exactly as written in a `.mtl` file.
///
/// Kept as the raw Phong-era record so the parser stays a faithful reader of the
/// format; the conversion to the shared [SurfaceMaterial] happens in the loader,
/// where the approximation can be documented in one place.
final class MtlMaterial {
  const MtlMaterial({
    required this.name,
    this.diffuse,
    this.specular,
    this.specularExponent,
    this.opacity = 1.0,
    this.diffuseTexturePath,
  });

  final String name;

  /// `Kd`, in the 0..1 range and authored non-linearly.
  final Vector3? diffuse;

  /// `Ks`.
  final Vector3? specular;

  /// `Ns`, the Phong exponent, roughly 0..1000.
  final double? specularExponent;

  /// `d`, or `1 - Tr`.
  final double opacity;

  /// `map_Kd`, relative to the `.mtl` file.
  final String? diffuseTexturePath;

  /// Perceptual roughness approximated from the Phong exponent.
  ///
  /// There is no correct conversion — Phong's exponent and GGX roughness describe
  /// different lobes — but the mapping below is the common one and keeps the
  /// ordering intuitive: a high exponent reads as a tight highlight, i.e. smooth.
  double get approximateRoughness {
    final exponent = specularExponent;
    if (exponent == null) return 0.5;
    if (exponent <= 0.0) return 1.0;
    return (1.0 - (exponent / 1000.0).clamp(0.0, 1.0)).clamp(0.02, 1.0);
  }

  /// Metallic approximated from the specular colour.
  ///
  /// OBJ has no notion of metalness. A bright, near-neutral `Ks` is the closest
  /// signal a Phong material gives, so it is mapped conservatively: most OBJ
  /// materials should come out dielectric rather than accidentally chrome.
  double get approximateMetallic {
    final ks = specular;
    if (ks == null) return 0.0;
    final brightness = (ks.x + ks.y + ks.z) / 3.0;
    return brightness > 0.9 ? 0.5 : 0.0;
  }
}

/// The decoded contents of an OBJ file.
///
/// A [ModelDocument], so it shares materials, images and surfaces with the glTF
/// decoder and can be uploaded by the same code.
final class ObjDocument extends ModelDocument {
  const ObjDocument({
    required this.surfaces,
    required this.materials,
    required this.images,
    required this.warnings,
    this.materialNames = const <String>[],
  });

  @override
  final List<ModelSurface> surfaces;

  @override
  final List<SurfaceMaterial> materials;

  @override
  final List<EncodedImage> images;

  @override
  final List<String> warnings;

  /// Names parallel to [materials], preserving what `usemtl` referred to.
  final List<String> materialNames;

  @override
  String toString() => 'ObjDocument(${surfaces.length} surfaces, $vertexCount '
      'vertices, $triangleCount triangles, ${materials.length} materials)';
}
