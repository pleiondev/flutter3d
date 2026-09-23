/// Merging a run of identical opaque draws into one instanced call —
/// `gfx-67n`.
///
/// A `part` of `renderer.dart` — see `renderer_shadow_pass.dart` for why.
///
/// **The run is already there to be found.** `SortMode.stateThenDepth` orders
/// the opaque half by pipeline and then by material, so a hundred nodes sharing
/// a geometry and a material arrive next to each other. What this does is
/// notice, fill a pooled batch with their world transforms and draw it once.
///
/// It is off unless `RenderSettings.batchIdenticalDraws` asks for it, and the
/// reason is arithmetic rather than caution: the two vertex stages do not
/// compute the same numbers. See that setting for the two places they differ.
part of 'renderer.dart';

extension _BatchedDraws on Renderer {
  /// Encodes the opaque half, merging runs of identical draws.
  ///
  /// [encode] is the same per-node procedure the unbatched path uses, handed in
  /// rather than reached for, because the closure it comes from is where this
  /// frame's lights, shadows and pass state live.
  void _encodeBatchedOpaque({
    required List<int> indices,
    required _SceneProbes probes,
    required void Function(MeshNode node) encode,
  }) {
    var i = 0;
    while (i < indices.length) {
      final first = _renderList.itemAt(indices[i]).requireNode;

      if (!_isBatchable(first)) {
        encode(first);
        i++;
        continue;
      }

      // The probe a member reflects is chosen by where it is, so two nodes that
      // agree on everything else and sit either side of a probe boundary are
      // two different draws and must stay two.
      final probe = probes.nearest(first.worldBoundsCentre);

      var end = i + 1;
      while (end < indices.length) {
        final next = _renderList.itemAt(indices[end]).requireNode;
        if (!_isBatchable(next) ||
            !identical(next.mesh, first.mesh) ||
            !identical(next.material, first.material) ||
            next.worldIsMirrored != first.worldIsMirrored ||
            !identical(probes.nearest(next.worldBoundsCentre), probe)) {
          break;
        }
        end++;
      }

      final run = end - i;
      if (run < RenderSettings.batchRunMinimum) {
        for (var k = i; k < end; k++) {
          encode(_renderList.itemAt(indices[k]).requireNode);
        }
        i = end;
        continue;
      }

      final batch = _batchFor(first)
        ..clear()
        ..ensureCapacity(run);
      for (var k = i; k < end; k++) {
        batch.addInstance(
          _renderList.itemAt(indices[k]).requireNode.worldMatrix,
        );
      }

      // The batch's own centre is the middle of the run, not of any member, so
      // it can land on the other side of a probe boundary from the members that
      // agreed with each other. Rather than reason about when that can happen,
      // ask — and draw the run one at a time when the answer differs.
      if (!identical(probes.nearest(batch.worldBoundsCentre), probe)) {
        for (var k = i; k < end; k++) {
          encode(_renderList.itemAt(indices[k]).requireNode);
        }
        i = end;
        continue;
      }

      encode(batch);
      _batchedDraws += run;
      i = end;
    }
  }

  /// Whether [node] can be one instance of a batch.
  ///
  /// Everything excluded here is excluded because the instanced stage would
  /// draw it differently, not because it would be awkward. A skinned mesh has
  /// its own stage and its own layout; a morphed one carries weights the batch
  /// would have to hold per instance; a lightmapped one reads its colour
  /// attribute as a lightmap coordinate, which the instanced stage spends on
  /// the instance tint; and a batch is already a batch.
  bool _isBatchable(MeshNode node) =>
      node is! InstancedMeshNode &&
      node.skeleton == null &&
      node.morph == null &&
      !node.lightmapped &&
      node.mesh is DrawableGeometry;

  /// The pooled batch for [node]'s mesh and material.
  ///
  /// Pooled by the pair rather than made per frame, so a scene whose runs are
  /// the same every frame allocates nothing after the first: the buffer is
  /// refilled in place and `ensureCapacity` only grows. A pair no view drew
  /// with for a whole frame is dropped by [_retireUnusedBatches].
  InstancedMeshNode _batchFor(MeshNode node) {
    final key = _BatchKey(node.mesh, node.material);
    _batchesUsed.add(key);
    return _batchPool[key] ??= InstancedMeshNode(
      node.mesh,
      node.material,
      capacity: RenderSettings.batchRunMinimum,
      name: 'auto batch',
    );
  }

  /// Drops every pooled batch the last frame did not draw with.
  ///
  /// Called once at the top of a frame. The pool is keyed by the mesh and the
  /// material themselves, so without this it held both — and the material's
  /// textures — for as long as the renderer lived, whatever the scene had
  /// since let go of.
  void _retireUnusedBatches() {
    if (_batchPool.isEmpty) return;
    _batchPool.removeWhere((key, _) => !_batchesUsed.contains(key));
    _batchesUsed.clear();
  }
}

/// A mesh and a material, by identity, as one map key.
final class _BatchKey {
  const _BatchKey(this.mesh, this.material);

  final MeshGeometry mesh;
  final Material material;

  @override
  bool operator ==(Object other) =>
      other is _BatchKey &&
      identical(other.mesh, mesh) &&
      identical(other.material, material);

  @override
  int get hashCode =>
      Object.hash(identityHashCode(mesh), identityHashCode(material));
}
