part of 'modifier.dart';

/// [count] copies of the base mesh, each shifted by one more [offset] than
/// the last, welded along any seam closer than [mergeDistance].
///
/// **Rebuilt through [EditMeshBuilder] rather than grown in place**, the same
/// choice [mergeByDistance] itself makes and for the same reason: a fresh
/// build is a vertex list and a face list, and there is no half-edge
/// bookkeeping to get wrong copying either one `count` times.
///
/// **Carries positions, faces and each face's material slot; does not yet
/// carry UV, colour, crease, edge flags or skin weights.** Nothing that
/// exists yet — `mesh-42`'s own acceptance is a vertex count and a volume —
/// asks for those, and copying a per-corner attribute correctly needs each
/// copy's half-edges lined up with the original's one at a time, which is
/// real work worth doing when something actually depends on it rather than
/// carried here on the chance it might.
final class ArrayModifier extends Modifier {
  const ArrayModifier({
    required this.count,
    required this.offset,
    this.mergeDistance,
  });

  /// Total instances in the result, the original included — `count: 1` is
  /// every array modifier's own identity, not a special case handled apart
  /// from the loop below.
  final int count;

  /// Added to every vertex, once per copy after the first: copy `i` sits at
  /// `original + offset * i`.
  final Vector3 offset;

  /// Vertices within this of each other are welded after every copy is
  /// placed, or left alone when null — the two are different answers on
  /// purpose: `0` still runs [mergeByDistance] and welds only vertices that
  /// land exactly together (`offset` chosen so copies touch), while `null`
  /// skips the pass entirely for a caller that knows its copies never meet.
  final double? mergeDistance;

  @override
  EditMesh apply(EditMesh base, ModifierContext context) {
    if (count < 1) {
      throw ArgumentError('ArrayModifier.count must be at least 1, was $count');
    }

    final builder = EditMeshBuilder();
    final liveVertices = <int>[
      for (var v = 0; v < base.vertexSlotCount; v++)
        if (base.isVertexAlive(v)) v,
    ];
    final baseFaces = base.faces();
    final baseSlots = <int>[
      for (var f = 0; f < base.faceSlotCount; f++)
        if (base.isFaceAlive(f)) base.materialSlotOf(f),
    ];
    final hasSlots = base.hasLayer(MeshDomain.face, MeshAttribute.materialSlot);
    final newFaces = <int>[];

    for (var copy = 0; copy < count; copy++) {
      final shift = offset.clone()..scale(copy.toDouble());
      final remap = <int, int>{
        for (final int old in liveVertices)
          old: builder.addVertex(base.positionOf(old) + shift),
      };
      for (var i = 0; i < baseFaces.length; i++) {
        newFaces.add(
          builder.addFace(<int>[for (final int v in baseFaces[i]) remap[v]!]),
        );
      }
    }

    var result = builder.build();
    if (hasSlots) {
      result.beginStep();
      for (var copy = 0; copy < count; copy++) {
        for (var i = 0; i < baseFaces.length; i++) {
          result.setMaterialSlot(
            newFaces[copy * baseFaces.length + i],
            baseSlots[i],
          );
        }
      }
      result.endStep();
    }
    if (mergeDistance != null) {
      final (EditMesh merged, _) = mergeByDistance(
        result,
        distance: mergeDistance,
      );
      result = merged;
    }
    return result;
  }

  @override
  Map<String, Object?> toJson() => <String, Object?>{
    'kind': 'array',
    'count': count,
    'offset': <double>[offset.x, offset.y, offset.z],
    'mergeDistance': mergeDistance,
  };

  /// [ArrayModifier] from its own [toJson], or null when a field is missing
  /// or of the wrong type.
  static ArrayModifier? fromJson(Map<String, Object?> json) => switch ((
    json['count'],
    json['offset'],
  )) {
    (final int count, [final num x, final num y, final num z]) => ArrayModifier(
      count: count,
      offset: Vector3(x.toDouble(), y.toDouble(), z.toDouble()),
      mergeDistance: switch (json['mergeDistance']) {
        final num d => d.toDouble(),
        _ => null,
      },
    ),
    _ => null,
  };
}
