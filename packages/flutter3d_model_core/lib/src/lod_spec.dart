/// One level of detail an object can fall back to — `pro-lod-03`'s own row.
library;

/// A target ratio and the screen size below which it takes over.
///
/// **A recipe, not a mesh.** Simplifying is real work —
/// `simplifyMeshWithAttributes` (`pro-lod-01`/`pro-lod-02`, in
/// `flutter3d_mesh`) walks every triangle of the base mesh — so a `LodSpec`
/// only ever holds what was asked for; `LodMeshCache` (`lod_cache.dart`) is
/// what turns one into an actual `MeshData`, generated once per
/// `ModelObject.version` and kept until either the ratio changes or the
/// base mesh does.
///
/// [ratio] and [maxScreenFraction] are the same two numbers
/// `packages/flutter3d`'s own `LodLevel` already needs to build a
/// `LodGroup` — this is the editor-side half that says how each level was
/// made, where `LodLevel` is the viewport-side half that only cares what it
/// looks like once made.
final class LodSpec {
  const LodSpec({required this.ratio, required this.maxScreenFraction});

  /// Target triangle count against the base mesh's own, as a fraction in
  /// `(0, 1]` — `1.0` asks for no reduction at all, which
  /// `simplifyMesh`/`simplifyMeshWithAttributes` already hand back
  /// unchanged rather than doing free work to produce a copy.
  final double ratio;

  /// Fraction of the viewport's height below which this level is used —
  /// `LodLevel.maxScreenFraction`'s own meaning in `package:flutter3d`,
  /// carried here so a project file can say how a level was chosen without
  /// depending on the engine that consumes it.
  final double maxScreenFraction;

  LodSpec copyWith({double? ratio, double? maxScreenFraction}) => LodSpec(
    ratio: ratio ?? this.ratio,
    maxScreenFraction: maxScreenFraction ?? this.maxScreenFraction,
  );

  @override
  String toString() =>
      'LodSpec(ratio: $ratio, maxScreenFraction: $maxScreenFraction)';
}
