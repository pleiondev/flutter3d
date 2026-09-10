/// Keeps the scene the renderer draws in step with the project the commands
/// change.
///
/// **Two graphs, on purpose, and this is the seam between them.** A
/// `ModelProject` is a value with no GPU in it — that is what lets a
/// command-line exporter and an agent hold one — and a `Scene` is a tree of
/// nodes holding uploaded buffers. Making the project hold `DeviceMesh`es would
/// put a device in the document; making the scene the document would put undo
/// in the renderer. So the project changes and this walks the difference.
///
/// **The difference is found by version, not by comparison.** Every change to a
/// `ModelObject` gives it a new one, so an object whose version has not moved
/// has not changed and its buffers are still right. Comparing meshes instead
/// costs more than the upload it would save, which is the whole reason the
/// version is on the object.
///
/// **What is uploaded again is decided by what changed.** A moved object is a
/// matrix; a cut mesh is a buffer. Both come through `version`, so this asks a
/// second question — whether the geometry is the same object as last time —
/// before paying for an upload. A drag of a hundred frames uploads nothing.
library;

import 'package:flutter3d/flutter3d.dart' hide Material;
import 'package:flutter3d/flutter3d.dart' as engine show Material;
import 'package:flutter3d_model_core/flutter3d_model_core.dart';
import 'package:vector_math/vector_math.dart';

/// One object's node, and what it was built from.
final class _Tracked {
  _Tracked(this.node, this.version, this.geometry);

  final MeshNode node;
  int version;
  Geometry geometry;
}

/// The scene, following a project.
final class SceneSync {
  SceneSync({required this.device, required this.scene, required this.root});

  final GraphicsDevice device;
  final Scene scene;

  /// What every object's node hangs under. A node of its own rather than the
  /// scene, so the lights and the camera are not among the things a pick has to
  /// walk past and a `frameSubject` has something to measure.
  final SceneNode root;

  final Map<int, _Tracked> _tracked = <int, _Tracked>{};

  /// The node drawn for [id], or null.
  MeshNode? nodeOf(int id) => _tracked[id]?.node;

  /// Which object [node] — or anything above it — was drawn for.
  ///
  /// **Up the parents, because what a pick answers with is the leaf that was
  /// rasterised.** One object is one node today and will be several the day a
  /// model that was imported keeps its material split, and a lookup that only
  /// knew leaves would answer "nothing" for exactly those.
  int? objectOf(SceneNode? node) {
    for (var at = node; at != null; at = at.parent) {
      for (final MapEntry<int, _Tracked> each in _tracked.entries) {
        if (identical(each.value.node, at)) return each.key;
      }
    }
    return null;
  }

  /// Brings the scene to [project].
  ///
  /// Returns how many geometries were uploaded, which is what a test asserts on
  /// and what a profile reads: the number that must be zero while somebody is
  /// dragging.
  int apply(ModelProject project) {
    var uploaded = 0;
    final seen = <int>{};

    for (final ModelObject object in project.objects) {
      seen.add(object.id);
      final _Tracked? had = _tracked[object.id];

      if (had == null) {
        final MeshNode node = MeshNode(
          DeviceMesh.upload(device, _dataOf(object.geometry)),
          _clay(),
          name: object.name,
        );
        node.setLocalMatrix(object.transform);
        root.add(node);
        _tracked[object.id] = _Tracked(node, object.version, object.geometry);
        uploaded++;
        continue;
      }
      if (had.version == object.version) continue;

      // The version moved, so something changed. Which something decides
      // whether a buffer is rebuilt: a matrix is free and a mesh is not.
      if (!identical(had.geometry, object.geometry)) {
        had.node.mesh = DeviceMesh.upload(device, _dataOf(object.geometry));
        had.geometry = object.geometry;
        uploaded++;
      }
      had.node
        ..name = object.name
        ..setLocalMatrix(object.transform);
      had.version = object.version;
    }

    // Anything the project no longer holds. Removed after the pass rather than
    // during it, because a map cannot be walked while it is being changed and
    // because an object that moved under a new parent is not a removal.
    for (final int id in _tracked.keys.toList()) {
      if (seen.contains(id)) continue;
      final _Tracked gone = _tracked.remove(id)!;
      gone.node.parent?.remove(gone.node);
    }

    _reparent(project);
    return uploaded;
  }

  /// Hangs each node under the node of its object's parent.
  ///
  /// A second pass, because a child can come before its parent in the list —
  /// an object reparented under one added after it — and a first pass would
  /// then be looking for a node that does not exist yet.
  void _reparent(ModelProject project) {
    for (final ModelObject object in project.objects) {
      final _Tracked? tracked = _tracked[object.id];
      if (tracked == null) continue;
      final SceneNode want =
          (object.parent == null ? null : _tracked[object.parent]?.node) ??
          root;
      if (identical(tracked.node.parent, want)) continue;
      tracked.node.parent?.remove(tracked.node);
      want.add(tracked.node);
    }
  }

  /// The buffers a geometry draws as.
  static MeshData _dataOf(Geometry geometry) => switch (geometry) {
    ParametricGeometry(:final shape) => shape.drawn.build(),
    EditedGeometry(:final mesh) => mesh.toMeshData(),
    ImportedGeometry(:final data) => data,
  };

  /// The colour of unpainted clay, which is what an object with no material yet
  /// should look like: a shape being judged by its form.
  ///
  /// One per node rather than one shared, because a material is what `mat-01`
  /// will assign per object and sharing them now would mean unpicking it then.
  static engine.Material _clay() => engine.Material(
    name: 'clay',
    lighting: LightingModel.pbr,
    baseColor: Vector4(0.72, 0.70, 0.67, 1.0),
    roughness: 0.65,
  );
}
