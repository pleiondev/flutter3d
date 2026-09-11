part of 'modifier.dart';

/// A thin [Modifier] wrapper storing [mirror]'s own parameters, the same
/// split [ArrayModifier] makes between "the geometry" and "the stack step".
final class MirrorModifier extends Modifier {
  const MirrorModifier({
    required this.normal,
    this.mergeDistance,
    this.bisect = false,
    this.flipUv = false,
  });

  /// Which way the mirror plane, through the origin, faces. Normalised by
  /// [mirror] itself, so this need not already be unit length.
  final Vector3 normal;

  /// Vertices within this of each other, after mirroring, are welded — see
  /// [mirror]'s own doc comment for why a base already touching the plane
  /// needs this to end up as one closed shape rather than two overlapping
  /// ones with a doubled, inside-out wall down the middle.
  final double? mergeDistance;

  /// See [mirror]'s own doc comment: not built, and `apply` throws rather
  /// than mirroring the whole, unclipped mesh when this is true.
  final bool bisect;

  /// Stored and serialised, with no effect yet: [mirror] carries no UV
  /// across at all, the same documented gap [ArrayModifier] has for every
  /// per-corner attribute.
  final bool flipUv;

  @override
  EditMesh apply(EditMesh base, ModifierContext context) => mirror(
    base,
    normal: normal,
    mergeDistance: mergeDistance,
    bisect: bisect,
  );

  @override
  Map<String, Object?> toJson() => <String, Object?>{
    'kind': 'mirror',
    'normal': <double>[normal.x, normal.y, normal.z],
    'mergeDistance': mergeDistance,
    'bisect': bisect,
    'flipUv': flipUv,
  };

  /// [MirrorModifier] from its own [toJson], or null when a field is missing
  /// or of the wrong type.
  static MirrorModifier? fromJson(Map<String, Object?> json) => switch (json) {
    {
      'normal': [final num x, final num y, final num z],
      'bisect': final bool bisect,
      'flipUv': final bool flipUv,
    } =>
      MirrorModifier(
        normal: Vector3(x.toDouble(), y.toDouble(), z.toDouble()),
        bisect: bisect,
        flipUv: flipUv,
        mergeDistance: switch (json['mergeDistance']) {
          final num d => d.toDouble(),
          _ => null,
        },
      ),
    _ => null,
  };
}
