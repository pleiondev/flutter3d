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
import 'package:flutter3d_mesh/flutter3d_mesh.dart' show EditMesh, ShapeKey;
import 'package:flutter3d_model_core/flutter3d_model_core.dart';

import 'material_pool.dart';

/// One object's node, and what it was built from.
final class _Tracked {
  _Tracked(
    this.node,
    this.version,
    this.geometry,
    this.modifiers, {
    this.skeletonIndex,
    this.shapeSet = const ShapeSet(),
  });

  /// [ModelObject.shapeSet] as of the last upload — `ux-24`.
  ///
  /// **Its own field beside [geometry], because a weight moves neither.** A
  /// shape key dragged to one bumps the object's version and leaves
  /// `geometry` the identical instance it was, so the three questions above
  /// all answer "nothing changed" and the buffer keeps the base positions —
  /// which is exactly the bug the row found: the markers moved and the model
  /// did not.
  ShapeSet shapeSet;

  final MeshNode node;
  int version;
  Geometry geometry;

  /// [ModelObject.modifiers] as of the last time [node]'s mesh was
  /// uploaded — compared by identity against the project's current value
  /// on every [SceneSync.apply], the same way [geometry] already is.
  /// `ModelObject.copyWith`'s own `modifiers ?? this.modifiers` hands back
  /// a *new* list exactly when a modifier command actually touched the
  /// stack, so `identical` here is the same free, exact signal `geometry`
  /// gives for a mesh edit — see `tut-06`.
  List<ModifierSlot> modifiers;

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

  /// [ModelObject.modifiers], evaluated and cached per object — `tut-06`'s
  /// own fix. Before this, [apply] uploaded [ModelObject.geometry]
  /// straight through, so a mirror or an array modifier never reached the
  /// viewport until "Apply" baked it into the base mesh and dropped the
  /// stack; see [_meshFor].
  final ModifierEvaluationCache _modifiers = ModifierEvaluationCache();

  /// The evaluator, for the panel that wants to say what the stack costs —
  /// `ux-13`'s own "triangles in → out".
  ///
  /// **The same cache the viewport folds through, not a second one.** The
  /// number the panel shows has to be the number the picture is drawn from,
  /// and a second evaluator would fold the whole stack again to answer a
  /// question the first one has already answered this frame.
  ModifierEvaluationCache get modifiers => _modifiers;

  /// Set by [apply] when some object's own skeleton has more joints than the
  /// engine can skin — [Skeleton.maxJoints], the shader's own uniform-array
  /// limit — so a status line can say so instead of [Skeleton]'s constructor
  /// throwing past it, the same refusal `ModelInstance._buildSkeleton`
  /// already gives a glTF skin that arrives too large. Cleared at the top of
  /// every [apply] call, so this always answers the project's current shape
  /// rather than the first time it was ever true.
  String? skeletonOverflow;

  /// Objects this pass could not put on the GPU, by id, each with the reason
  /// — `ux-02`'s own row, and empty on every ordinary pass.
  ///
  /// **A failed upload used to take the whole session down.** The live run
  /// imported a real `.glb` over `--mcp-port` and got `DeviceBuffer creation
  /// failed` back with a stack; every call after it answered with the same
  /// stack, because the feed hook re-syncs the scene and the same object
  /// threw again, and a person watching the window saw nothing at all — the
  /// object was in the document, the status line counted its triangles, and
  /// the viewport was empty. One object the device will not take is a fact
  /// about that object: the rest of the project still draws, the document is
  /// untouched, and this is where the name goes so a status line and the
  /// outliner can say which one.
  ///
  /// Rebuilt on every [apply], like [skeletonOverflow], so an object that
  /// uploads on a later pass — a device that was out of memory for a moment,
  /// a geometry since repaired — stops being named without anything having
  /// to remember to clear it.
  final Map<int, String> unshowable = <int, String>{};

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
    unshowable.clear();

    for (final ModelObject object in project.objects) {
      seen.add(object.id);
      final _Tracked? had = _tracked[object.id];

      if (had == null) {
        final DeviceMesh? mesh = _upload(project, object);
        if (mesh == null) continue;
        final MeshNode node = MeshNode(
          mesh,
          _paintFor(object),
          name: object.name,
        );
        node.setLocalMatrix(object.transform);
        root.add(node);
        _tracked[object.id] = _Tracked(
          node,
          object.version,
          object.geometry,
          object.modifiers,
          skeletonIndex: object.skeletonIndex,
          shapeSet: object.shapeSet,
        );
        uploaded++;
        continue;
      }
      if (had.version == object.version) continue;

      // The version moved, so something changed. Which something decides
      // whether a buffer is rebuilt: a matrix is free and a mesh is not — a
      // skeleton newly bound or unbound is a second case, `view-27d`'s own
      // row, since it changes which `VertexLayout` this same `Geometry`
      // instance has to be read as without the instance itself changing —
      // and a modifier stack edited in place is a third, `tut-06`'s own
      // row: `AddModifier`/`ToggleModifier`/`SetModifierField` and the rest
      // all touch `ModelObject.modifiers`, never `.geometry`, so without
      // this check a mirror switched on mid-session would bump the
      // object's version and still upload nothing new.
      final bool reskinned = had.skeletonIndex != object.skeletonIndex;
      final bool modifiersChanged = !identical(had.modifiers, object.modifiers);
      // `ux-24`: a weight moved. `ModelObject.copyWith` hands back a new
      // `ShapeSet` exactly when a shape command touched one, so `identical`
      // is the same free, exact signal `modifiers` above already uses.
      final bool morphed = !identical(had.shapeSet, object.shapeSet);
      if (!identical(had.geometry, object.geometry) ||
          reskinned ||
          modifiersChanged ||
          morphed) {
        final DeviceMesh? mesh = _upload(project, object);
        // The node keeps whatever it was drawing last: a mesh the device
        // refused is not a reason to blank an object that was on screen a
        // frame ago, and `had` is left at its old version so the next pass
        // tries again rather than treating the refusal as done.
        if (mesh == null) continue;
        had.node.mesh = mesh;
        had.geometry = object.geometry;
        had.skeletonIndex = object.skeletonIndex;
        had.modifiers = object.modifiers;
        had.shapeSet = object.shapeSet;
        uploaded++;
      }
      had.node
        ..name = object.name
        ..material = _paintFor(object)
        ..setLocalMatrix(object.transform);
      had.version = object.version;
    }

    // `ux-14`: what is drawn, counting parents — a pass of its own, after
    // the one above, and deliberately not inside it.
    //
    // **Every tracked node, every time, regardless of its own version.**
    // Hiding a parent bumps the parent's version and nothing else's, so a
    // child whose version has not moved is exactly the node whose visibility
    // has to change — and that is the case the `continue`s above skip. The
    // walk is a handful of parent lookups per object and runs when a command
    // lands rather than per frame.
    for (final MapEntry<int, _Tracked> each in _tracked.entries) {
      each.value.node.visible = project.isVisible(each.key);
    }

    // Anything the project no longer holds. Removed after the pass rather than
    // during it, because a map cannot be walked while it is being changed and
    // because an object that moved under a new parent is not a removal.
    for (final int id in _tracked.keys.toList()) {
      if (seen.contains(id)) continue;
      final _Tracked gone = _tracked.remove(id)!;
      gone.node.parent?.remove(gone.node);
      _modifiers.forget(id);
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
  /// **It used to have to run before the stage's first frame, and the reason
  /// is worth keeping.** `SurfaceShading` and `WeightGradientShading` both
  /// record what a node was drawn with so they can put it back — and both
  /// recorded it the first time they saw the node and wrote that back on
  /// every frame afterwards, so a repaint was undone before anybody saw it
  /// and a document opened into a stage that had already drawn one frame
  /// stayed in clay. Both now remember only for as long as their own swap
  /// lasts (`display_modes.dart`, `weight_gradient.dart`), so this can be
  /// called at any point in a session — which is what `ModelerCubit`'s own
  /// material restage does after every command that edits one.
  void repaint(ModelProject project) {
    for (final ModelObject object in project.objects) {
      _tracked[object.id]?.node.material = _paintFor(object);
    }
  }

  /// [object]'s buffers on the device, or null with [unshowable] told why.
  ///
  /// **The catch is deliberately wide.** Everything from building the mesh
  /// data to allocating a buffer is on this path, and what a backend throws
  /// when it will not take a geometry is its own business — `flutter_gpu`
  /// raises a plain `Exception('DeviceBuffer creation failed')`, the software
  /// rasteriser something else entirely. Narrowing it by type would mean
  /// guessing the set, and a guess that is wrong here is the whole finding:
  /// one throw nobody caught, and the editor was unusable until it restarted.
  DeviceMesh? _upload(ModelProject project, ModelObject object) {
    try {
      return DeviceMesh.upload(
        device,
        _meshFor(project, object, _layoutFor(object)),
      );
    } catch (error) {
      unshowable[object.id] = '"${object.name}" could not be shown ($error)';
      return null;
    }
  }

  /// What [object] is painted with: its slot's material, or clay.
  engine.Material _paintFor(ModelObject object) =>
      materials?.forObject(object) ?? clay();

  /// The buffers [object] draws as, in [layout] — [object.geometry] run
  /// through its own modifier stack first when it has one enabled,
  /// [_dataOf] straight through otherwise.
  ///
  /// **Only an object with at least one enabled [ModifierSlot] pays for a
  /// stack evaluation at all.** [ModifierEvaluationCache.evaluatedMesh]
  /// would answer the same base mesh back for an empty or fully-disabled
  /// stack too, but the ordinary object — almost every one, `modifiers`'
  /// own doc comment says so — has none, and should cost exactly what it
  /// cost before `tut-06`: one switch over [Geometry], no fold.
  MeshData _meshFor(
    ModelProject project,
    ModelObject object,
    VertexLayout layout,
  ) {
    final bool hasEnabledModifier = object.modifiers.any(
      (ModifierSlot slot) => slot.enabled,
    );
    if (hasEnabledModifier) {
      final evaluated = _modifiers.evaluatedMesh(project, object);
      if (evaluated != null) {
        return _morphed(
          object,
          evaluated.toMeshData(layout: layout),
          evaluated,
        );
      }
    }
    final MeshData data = _dataOf(object.geometry, layout);
    return switch (object.geometry) {
      EditedGeometry(:final mesh) => _morphed(object, data, mesh),
      _ => data,
    };
  }

  MeshData _morphed(ModelObject object, MeshData data, EditMesh base) =>
      morphedForPreview(object.shapeSet, data, base);

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

/// [data] with [shapes] blended into its positions — `ux-24`.
///
/// **The viewport drew the base mesh and the markers moved.** A shape key at
/// weight one changed the document, changed the little points drawn over the
/// model, and left the model itself exactly where it was — so the one thing
/// a morph is for, seeing the expression, was the one thing the slider did
/// not do.
///
/// **Written into the buffer rather than into the mesh.** `EditMesh` is the
/// document's own geometry and a blend is a preview of it; writing the
/// blended positions back would make the preview the document and the slider
/// destructive. The `MeshData` this hands on is built fresh for the upload
/// and is nobody else's.
///
/// **Public and free-standing, because it is the arithmetic.** Whether the
/// viewport shows an expression is a question about three numbers per
/// vertex, and a test that had to build a device, a scene and a stage to ask
/// it would be a test of the staging. [SceneSync] is the one caller.
///
/// Costs nothing at all for an object with no keys or every weight at
/// nought, which is almost every object — the check is a walk of a list that
/// is usually empty.
MeshData morphedForPreview(ShapeSet shapes, MeshData data, EditMesh base) {
  if (shapes.keys.isEmpty) return data;
  if (!shapes.weights.any((double it) => it != 0.0)) return data;
  // A stack that changed the vertex count has left the keys naming slots
  // that are not there any more; `ShapeKey.blend` covers what it covers and
  // the rest keeps the base, which is the same "no data, no effect" rule
  // that file already states.
  final Float32List blended = ShapeKey.blend(base, shapes.keys, shapes.weights);
  final int stride = data.layout.floatsPerVertex;
  final int offset = data.layout.floatOffsetOf('position');
  if (offset < 0) return data;
  final Float32List vertices = Float32List.fromList(data.vertices);
  for (
    var vertex = 0;
    vertex * stride + offset + 2 < vertices.length;
    vertex++
  ) {
    if (vertex * 3 + 2 >= blended.length) break;
    final int at = vertex * stride + offset;
    vertices[at] = blended[vertex * 3];
    vertices[at + 1] = blended[vertex * 3 + 1];
    vertices[at + 2] = blended[vertex * 3 + 2];
  }
  return MeshData(
    layout: data.layout,
    vertices: vertices,
    indices: data.indices,
  );
}

/// [SceneSync.unshowable] as one sentence, or null when there is nothing to
/// say — `ux-02`'s own status line.
///
/// Names the first object and counts the rest, the shape
/// `ExportReadiness.says` already uses for the same problem: a status line
/// that lists every name is a status line nobody finishes reading, and the
/// first name is the one somebody can go and look at.
String? unshowableSaid(Map<int, String>? unshowable) {
  if (unshowable == null || unshowable.isEmpty) return null;
  final String first = unshowable.values.first;
  final int rest = unshowable.length - 1;
  return rest == 0 ? first : '$first (and $rest more)';
}
