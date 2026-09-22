/// One reading of one file: what a reader found in it, in the terms both
/// readers can be held to.
///
/// **Deliberately small, and the doc comment on [GodotCheck] says why each
/// field is here and each absent one is not.** A reading is not a document:
/// it has no node hierarchy, no vertex buffers and no materials beyond their
/// names, because those are the things two independent readers of the same
/// glTF legitimately disagree about.
library;

/// One surface as a reader found it.
final class SurfaceReading {
  const SurfaceReading({
    required this.material,
    required this.triangles,
    required this.min,
    required this.max,
    this.skinned = false,
  });

  /// The material's name, or the empty string when the surface has none.
  /// Half of the key surfaces are paired by.
  final String material;

  /// The other half of that key.
  final int triangles;

  /// Whether a skin moves this surface. Our document's fact, not Godot's:
  /// Godot pads a skinned mesh's bounds to cover where the skeleton can take
  /// it, so a skinned pair is only asked for containment.
  final bool skinned;

  /// The mesh's own bounds, in its own space — no node transform applied, so
  /// the two readers are talking about the same numbers.
  final List<double> min;
  final List<double> max;

  /// What the surface is called in a sentence about it.
  String get group =>
      '${material.isEmpty ? '(no material)' : material} × $triangles triangles';

  @override
  String toString() =>
      '$group '
      '[${min.map((v) => v.toStringAsFixed(4)).join(', ')}] '
      '[${max.map((v) => v.toStringAsFixed(4)).join(', ')}]';
}

/// One file as a reader found it.
final class FileReading {
  const FileReading({required this.surfaces, this.error});

  /// Present when the reader could not read the file at all. Every other
  /// field is then meaningless and the comparison says only this.
  final String? error;

  final List<SurfaceReading> surfaces;

  int get triangles =>
      surfaces.fold(0, (sum, surface) => sum + surface.triangles);

  /// Every material named by a surface. The empty name is not one.
  Set<String> get materials => <String>{
    for (final surface in surfaces)
      if (surface.material.isNotEmpty) surface.material,
  };
}
