/// The mesh each of an object's own [LodSpec]s actually produces, cached
/// across calls — `pro-lod-03`'s own row.
///
/// **The same bargain [ReadinessCache] strikes, for the same reason.**
/// Generating a level is a real `simplifyMeshWithAttributes` pass over
/// however many triangles the base mesh has — free for a small prop, a
/// second or more for a dense one — and a viewport that asks for the same
/// object's LODs every frame should not pay that twice between edits.
/// [ModelObject.version] is the key, exactly as it is there: `copyWith` is
/// the only way to produce a changed object and it always moves the
/// version on, so an object whose version has not moved has the mesh it
/// had last time for a level whose ratio has not moved either.
///
/// **Keyed on version rather than on [ModelObject.geometry]'s identity**,
/// unlike [ModifierEvaluationCache] — deliberately the coarser of the two
/// choices. A modifier stack re-evaluates on every frame a viewport draws,
/// so a rename forcing a re-fold there would be a real, felt cost; a LOD is
/// regenerated the rare times someone adds one, changes its ratio, or edits
/// the mesh it is built from, so a rename also invalidating it costs one
/// unnecessary simplification pass rather than one every frame. Trading
/// that away for a single, simpler key — the one field every command that
/// changes anything about an object already has to bump — is the cheaper
/// mistake to make.
library;

import 'package:flutter3d_geometry/flutter3d_geometry.dart';
import 'package:flutter3d_mesh/flutter3d_mesh.dart';

import 'lod_spec.dart';
import 'project.dart';

final class _CachedLod {
  const _CachedLod(this.baseVersion, this.mesh);

  final int baseVersion;
  final MeshData mesh;
}

/// The simplified mesh each `(objectId, lodIndex)` pair produces, kept until
/// the object's own version moves past the one it was generated at.
final class LodMeshCache {
  final Map<int, Map<int, _CachedLod>> _byObjectId =
      <int, Map<int, _CachedLod>>{};

  /// The mesh `object.lods[lodIndex]` describes, generating and remembering
  /// it when nothing cached yet answers for [ModelObject.version] — or null
  /// when [lodIndex] is out of range or [object] has no mesh to simplify at
  /// all (a parametric shape not yet baked, or a socket).
  MeshData? meshFor(ModelObject object, int lodIndex) {
    if (lodIndex < 0 || lodIndex >= object.lods.length) return null;
    final MeshData? base = _baseMeshOf(object);
    if (base == null) return null;

    final byLod = _byObjectId.putIfAbsent(object.id, () => <int, _CachedLod>{});
    final _CachedLod? cached = byLod[lodIndex];
    if (cached != null && cached.baseVersion == object.version) {
      return cached.mesh;
    }

    final LodSpec spec = object.lods[lodIndex];
    final int target = (base.triangleCount * spec.ratio).round().clamp(
      1,
      base.triangleCount,
    );
    final MeshData mesh = simplifyMeshWithAttributes(
      base,
      targetTriangleCount: target,
    );
    byLod[lodIndex] = _CachedLod(object.version, mesh);
    return mesh;
  }

  /// Drops every cached level for [objectId], so the next [meshFor] call
  /// regenerates it whatever [ModelObject.version] says.
  ///
  /// **The one door version-keying alone cannot open.** [RegenerateLods]
  /// bumps the object's own version, which already makes every ordinary
  /// [meshFor] call regenerate — that is enough for "the base mesh changed".
  /// This is for the other reason `pro-lod-03`'s own row names: the
  /// simplification algorithm itself changed underneath every project, and
  /// a cache holding meshes built by the old one has no version number that
  /// would ever tell it so on its own.
  void invalidate(int objectId) => _byObjectId.remove(objectId);

  /// Drops [objectId] from this cache entirely — an object the project no
  /// longer holds should not keep its last generated LOD meshes alive for
  /// nothing, the same reason [ModifierEvaluationCache.forget] exists.
  void forget(int objectId) => _byObjectId.remove(objectId);

  /// The mesh [object]'s base geometry actually holds, or null when there is
  /// none to simplify — the same restriction [ModifierEvaluationCache]
  /// documents for the same reason: only a real triangle mesh has anything
  /// for `simplifyMeshWithAttributes` to walk.
  MeshData? _baseMeshOf(ModelObject object) => switch (object.geometry) {
    EditedGeometry(:final mesh) => mesh.toMeshData(),
    ImportedGeometry(:final data) => data,
    _ => null,
  };
}
