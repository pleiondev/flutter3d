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

import 'material_pool.dart';

/// One object's node, and what it was built from.
final class _Tracked {
  _Tracked(this.node, this.version, this.geometry);

  final MeshNode node;
  int version;
  Geometry geometry;
}

/// The scene, following a project.
final class SceneSync {
  SceneSync({
    required this.device,
    required this.scene,
    required this.root,
    this.materials,
  });

  final GraphicsDevice device;
  final Scene scene;

  /// The project's materials, uploaded. Null for the measurement stands, which
  /// have no document and want the clay.
  ///
  /// Read rather than owned: filling it is asynchronous — a texture has to be
  /// decoded — and [apply] runs where nothing can wait. Whoever fills it calls
  /// [repaint] afterwards.
  final MaterialPool? materials;

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
          _paintFor(object),
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
        ..material = _paintFor(object)
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

  /// Re-reads every node's material from the pool.
  ///
  /// **What closes the gap between an upload and a frame.** [apply] cannot wait
  /// for a texture to decode, so the first pass over a freshly opened model
  /// paints everything in clay; once the pool is filled, this puts the paint on
  /// without touching a vertex buffer. Calling [apply] again instead would work
  /// and would compare every mesh to decide it had not changed.
  ///
  /// **This has to run before the stage's first frame, and the reason is in
  /// `display_modes.dart`.** `SurfaceShading` records what each node was drawn
  /// with the first time it sees one, so that switching to the normals view and
  /// back can put it back. A repaint after that first sight changes the node
  /// and not the record, and the next frame in material mode writes the
  /// remembered clay straight back over the paint. Opening is safe because
  /// `openDocument` repaints before the stage reaches the screen; whatever
  /// changes a material later has to make the shading forget the node too.
  void repaint(ModelProject project) {
    for (final ModelObject object in project.objects) {
      _tracked[object.id]?.node.material = _paintFor(object);
    }
  }

  /// What [object] is painted with: its slot's material, or clay.
  engine.Material _paintFor(ModelObject object) =>
      materials?.forObject(object) ?? clay();

  /// The buffers a geometry draws as.
  static MeshData _dataOf(Geometry geometry) => switch (geometry) {
    ParametricGeometry(:final shape) => shape.drawn.build(),
    EditedGeometry(:final mesh) => mesh.toMeshData(),
    ImportedGeometry(:final data) => data,
  };
}
