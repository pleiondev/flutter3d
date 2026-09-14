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

import 'dart:typed_data';

import 'package:flutter3d/flutter3d.dart' hide Material;
import 'package:flutter3d/flutter3d.dart' as engine show Material;
import 'package:flutter3d_model_core/flutter3d_model_core.dart';

import 'material_pool.dart';

/// One object's node, and what it was built from.
final class _Tracked {
  _Tracked(this.node, this.version, this.geometry, {this.skeletonIndex});

  final MeshNode node;
  int version;
  Geometry geometry;

  /// [ModelObject.skeletonIndex] as of the last time [node]'s mesh was
  /// uploaded. Compared against the project's current value on every
  /// [SceneSync.apply] — separately from [geometry], since a bind (or an
  /// unbind) changes which [VertexLayout] the very same [Geometry] instance
  /// has to be read as, without the instance itself ever being replaced.
  int? skeletonIndex;

  /// The [ProjectSkeleton] [node.skeleton] was last built from, by identity.
  /// `AddJoint`/`RemoveJoint`/`ReparentJoint` and the rest all rewrite
  /// `ModelProject.skeletons[index]` in place rather than touching this
  /// object, so a bumped [ModelObject.version] is not something
  /// [SceneSync._syncSkeletons] can wait for — this is what it compares
  /// instead.
  ProjectSkeleton? skeletonSource;
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

  /// Set by [apply] when some object's own skeleton has more joints than the
  /// engine can skin — [Skeleton.maxJoints], the shader's own uniform-array
  /// limit — so a status line can say so instead of [Skeleton]'s constructor
  /// throwing past it, the same refusal `ModelInstance._buildSkeleton`
  /// already gives a glTF skin that arrives too large. Cleared at the top of
  /// every [apply] call, so this always answers the project's current shape
  /// rather than the first time it was ever true.
  String? skeletonOverflow;

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
    skeletonOverflow = null;

    for (final ModelObject object in project.objects) {
      seen.add(object.id);
      final _Tracked? had = _tracked[object.id];

      if (had == null) {
        final MeshNode node = MeshNode(
          DeviceMesh.upload(
            device,
            _dataOf(object.geometry, _layoutFor(object)),
          ),
          _paintFor(object),
          name: object.name,
        );
        node.setLocalMatrix(object.transform);
        root.add(node);
        _tracked[object.id] = _Tracked(
          node,
          object.version,
          object.geometry,
          skeletonIndex: object.skeletonIndex,
        );
        uploaded++;
        continue;
      }
      if (had.version == object.version) continue;

      // The version moved, so something changed. Which something decides
      // whether a buffer is rebuilt: a matrix is free and a mesh is not — and
      // a skeleton newly bound or unbound is a third case, `view-27d`'s own
      // row, since it changes which `VertexLayout` this same `Geometry`
      // instance has to be read as without the instance itself changing.
      final bool reskinned = had.skeletonIndex != object.skeletonIndex;
      if (!identical(had.geometry, object.geometry) || reskinned) {
        had.node.mesh = DeviceMesh.upload(
          device,
          _dataOf(object.geometry, _layoutFor(object)),
        );
        had.geometry = object.geometry;
        had.skeletonIndex = object.skeletonIndex;
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
    _syncSkeletons(project);
    return uploaded;
  }

  /// [VertexLayout.skinned] for an object bound to a skeleton,
  /// [VertexLayout.standard] otherwise — `view-27d`'s own switch, read off
  /// the document itself rather than off whatever layout the geometry
  /// already happens to hold, so a mesh gains the skinning attributes the
  /// moment `BindSkin`/`SetRig` gives it a [ModelObject.skeletonIndex], with
  /// no separate command ever telling the viewport to look again.
  static VertexLayout _layoutFor(ModelObject object) =>
      object.skeletonIndex == null
      ? VertexLayout.standard
      : VertexLayout.skinned;

  /// Attaches (or refreshes) the engine [Skeleton] behind every skinned
  /// object, once every node [project] names has one in [_tracked] — which
  /// is why this runs after [_reparent] rather than inside the loop above: a
  /// mesh listing joint 7 among its own [ProjectSkeleton.joints] before
  /// object 7 has itself been walked would otherwise find nothing yet to
  /// hang the skeleton on.
  void _syncSkeletons(ModelProject project) {
    for (final ModelObject object in project.objects) {
      final _Tracked? tracked = _tracked[object.id];
      if (tracked == null) continue;

      final int? index = object.skeletonIndex;
      if (index == null || index < 0 || index >= project.skeletons.length) {
        if (tracked.skeletonSource != null) {
          tracked.node.skeleton = null;
          tracked.skeletonSource = null;
        }
        continue;
      }

      final ProjectSkeleton skeleton = project.skeletons[index];
      // Compared by identity, not by content or by `ModelObject.version` —
      // see [_Tracked.skeletonSource]'s own doc comment for why a joint
      // command can move this without moving that.
      if (identical(tracked.skeletonSource, skeleton)) continue;

      // `Skeleton`'s own constructor throws past this many joints — the
      // shader's uniform array is a hard limit, not a preference — so this is
      // refused the same way `ModelInstance._buildSkeleton` already refuses
      // an over-long glTF skin: reported, never thrown.
      if (skeleton.joints.length > Skeleton.maxJoints) {
        skeletonOverflow =
            '"${object.name}" has ${skeleton.joints.length} joints; the '
            'viewport can only skin ${Skeleton.maxJoints}';
        continue;
      }

      final joints = <SceneNode>[];
      for (final int jointId in skeleton.joints) {
        final MeshNode? node = nodeOf(jointId);
        if (node == null) break;
        joints.add(node);
      }
      // A joint this pass has not reached yet — a document mid-edit inside
      // one `ModelHistory` transaction, say — or one the project has lost
      // entirely; either way left for the next `apply` rather than hung on a
      // skeleton with a hole in it.
      if (joints.length != skeleton.joints.length) continue;

      tracked.node
        ..skeleton = Skeleton(
          name: skeleton.name,
          joints: joints,
          inverseBindMatrices: skeleton.inverseBindMatrices,
        )
        // Measured from this upload's own bind pose, the same call
        // `ModelInstance` makes for a glTF skin — see [MeshNode.skinReach]'s
        // own doc comment for why the mesh's *local* radius is what belongs
        // here rather than anything measured in world space.
        ..skinReach = tracked.node.mesh.boundingRadius;
      tracked.skeletonSource = skeleton;
    }
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

  /// The buffers a geometry draws as, in [layout] — [_layoutFor]'s own
  /// answer for the object this geometry belongs to. Ignored for
  /// [ImportedGeometry], which arrives with a layout already baked in by
  /// whatever imported it, and for [SocketGeometry], which never has
  /// vertices to lay out at all.
  static MeshData _dataOf(Geometry geometry, VertexLayout layout) =>
      switch (geometry) {
        ParametricGeometry(:final shape) => shape.drawn.build(layout: layout),
        EditedGeometry(:final mesh) => mesh.toMeshData(layout: layout),
        ImportedGeometry(:final data) => data,
        // A socket draws nothing — see `SocketGeometry`'s own doc comment.
        SocketGeometry() => _empty,
      };

  /// What a socket uploads as: no vertices, no indices. One instance for all
  /// of them, the same reason `project_document.dart`'s own `_nothing` is.
  static final MeshData _empty = MeshData(
    layout: VertexLayout.standard,
    vertices: Float32List(0),
    indices: Uint32List(0),
  );
}
