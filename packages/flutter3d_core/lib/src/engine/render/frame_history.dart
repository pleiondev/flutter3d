/// What the previous frame looked like, for effects that need to know — `G2`.
///
/// A temporal resolve reprojects last frame's picture, and motion blur and
/// the velocity it needs are both "where was this a frame ago". Neither can
/// be answered from the scene, which only knows where things are now, so the
/// renderer keeps a copy of the few things that move: each mesh's world
/// matrix, its joint palette, its morph weights and its instance bytes, and
/// each view's unjittered view-projection.
///
/// **Per view, since 1.0.** "A frame ago" is the last frame *this view* was
/// drawn in, and two views drawn by separate `Renderer.render` calls — two
/// editor viewports, a minimap, a texture view drawn as a frame of its own —
/// each have their own. So each view keeps its own matrix and its own copy
/// of the nodes; the views of one `render` call (a stereo pair) share the
/// copy of the call's first view, because they saw the same scene.
///
/// **Copied only when something changed.** A node's change key is the
/// versions the scene already keeps — its world, its skeleton's pose, its
/// morph, its instance data — and a node whose key has not moved since the
/// last copy is not copied again. So a still scene costs a lookup a node and
/// allocates nothing after the first frame, which [allocations] counts.
///
/// **In the scene's space as it is now.** A `Scene.shiftOrigin` between two
/// frames moves every node by the shift; what was recorded before it is
/// moved by the same shift when it is read, so a floating origin is no
/// motion at all to the velocity and the resolve.
///
/// Off until something asks: [tracking] is false on a renderer whose frames
/// have nothing temporal in them, and the renderer skips the walk entirely.
library;

import 'dart:typed_data';

import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart'
    show WorldPosition;
import 'package:vector_math/vector_math.dart' as vm;

import '../scene/instanced_mesh_node.dart';
import '../scene/mesh_node.dart';
import 'render_view.dart';

/// One node as it was at the end of the last frame it was recorded in.
final class NodeHistory {
  NodeHistory._();

  /// The world matrix, in the scene's space as it is now (see [FrameHistory]
  /// on the floating origin).
  final vm.Matrix4 world = vm.Matrix4.zero();

  /// The joint palette, `Skeleton.matrices` as it was; null for a mesh with
  /// no skeleton.
  Float32List? joints;

  /// The morph weights; null for a mesh with no morph.
  Float32List? morphWeights;

  /// The drawn instances' bytes; null for a mesh that is not instanced.
  Float32List? instances;

  /// How many instances [instances] holds.
  int instanceCount = 0;

  /// The frame this was recorded at, `Renderer.frameIndex` before it moved.
  int frame = -1;

  (int, int, int, int) _key = (-1, -1, -1, -1);

  /// The scene origin [world] is relative to.
  double _originX = 0.0;
  double _originY = 0.0;
  double _originZ = 0.0;
}

/// The nodes one view (and the views drawn with it) saw.
final class _NodeStore {
  _NodeStore(this.owner);

  /// The view whose `render` call fills this store: the call's first view,
  /// or the view it was carried on to.
  RenderView owner;

  final Expando<NodeHistory> nodes = Expando<NodeHistory>('frame history');
}

final class _ViewHistory {
  _ViewHistory(this.store);

  final vm.Matrix4 matrix = vm.Matrix4.zero();
  int frame = -1;
  _NodeStore store;

  /// The scene origin [matrix] is relative to.
  /// In metres.
  double originX = 0.0;

  /// In metres.
  double originY = 0.0;

  /// In metres.
  double originZ = 0.0;
}

final class FrameHistory {
  /// Whether the renderer records a history at all. Set by whatever needs
  /// one; nothing in 0.8.0's defaults does.
  bool tracking = false;

  final Expando<_ViewHistory> _views = Expando<_ViewHistory>('view history');

  /// The scene origin of the frame being drawn; what was recorded relative
  /// to another is moved to this one when it is read.
  WorldPosition _origin = WorldPosition.origin;

  /// Buffers this history has created, for tests: an entry, a palette, a set
  /// of weights, an instance copy or a view matrix, each counted once when it
  /// is made or has to grow.
  int get allocations => _allocations;
  int _allocations = 0;

  /// Nodes copied, for tests: a node whose key did not move is not.
  int get copies => _copies;
  int _copies = 0;

  /// [node] as [view] last saw it, at the end of the last frame that drew
  /// [view], or null when it has not been recorded for that view — a node
  /// that has just appeared has no past, and an effect treats it as standing
  /// still.
  NodeHistory? of(MeshNode node, RenderView view) {
    final entry = _views[view]?.store.nodes[node];
    if (entry != null) _rebase(entry);
    return entry;
  }

  /// Whether [node] has changed since [view] last recorded it. False for a
  /// node never recorded, for the same reason [of] is null for one.
  bool moved(MeshNode node, RenderView view) {
    final entry = _views[view]?.store.nodes[node];
    return entry != null && entry._key != _keyOf(node);
  }

  /// The unjittered view-projection [view] was drawn with at the end of the
  /// last frame that drew it, or null when no frame has.
  ///
  /// **By view, since 1.0**, not by camera, not by the view's place in a
  /// list and not by the renderer's last frame: the list is the caller's and
  /// may be reordered between frames, two views of one camera — a stereo
  /// pair, two editor viewports — each have a last frame of their own, and a
  /// view drawn by a `render` call of its own is still answered after another
  /// call drew something else. The matrix is the camera's own
  /// (`CameraNode.viewProjection`), before any backend's depth range or
  /// framebuffer origin, so a reader adjusts it the way it adjusts the
  /// current one.
  vm.Matrix4? viewProjection(RenderView view) {
    final entry = _views[view];
    if (entry == null || entry.frame < 0) return null;
    // Recorded relative to another origin: the scene moved every node by
    // `from - to`, so a point now at `p` was at `p - d`, and the matrix that
    // drew it is `VP · T(-d)`.
    final dx = entry.originX - _origin.x;
    final dy = entry.originY - _origin.y;
    final dz = entry.originZ - _origin.z;
    if (dx != 0.0 || dy != 0.0 || dz != 0.0) {
      final m = entry.matrix.storage;
      for (var row = 0; row < 4; row++) {
        m[12 + row] -= m[row] * dx + m[4 + row] * dy + m[8 + row] * dz;
      }
      entry
        ..originX = _origin.x
        ..originY = _origin.y
        ..originZ = _origin.z;
    }
    return entry.matrix;
  }

  /// Records every node in [meshes] and every view in [views] with the
  /// matrix it drew with, as frame [frame]. The renderer's to call, once per
  /// `render`, when the frame is done. The nodes go into the first view's
  /// copy, which the others of the call share.
  void endFrame({
    required int frame,
    required Iterable<MeshNode> meshes,
    required Iterable<(RenderView, vm.Matrix4)> views,
  }) {
    _NodeStore? store;
    for (final (view, matrix) in views) {
      final entry = _views[view];
      if (store == null) {
        // The call's first view fills a copy of its own; one it shared with
        // another view's call starts its own now, with no past for a frame.
        final own = entry != null && identical(entry.store.owner, view)
            ? entry.store
            : _NodeStore(view);
        store = own;
        _recordView(entry, view, own, matrix, frame);
      } else {
        _recordView(entry, view, store, matrix, frame);
      }
    }
    if (store == null) return;
    for (final node in meshes) {
      _record(store, node, frame);
    }
  }

  void _recordView(
    _ViewHistory? entry,
    RenderView view,
    _NodeStore store,
    vm.Matrix4 matrix,
    int frame,
  ) {
    final target = entry ?? (_views[view] = _viewCreated(store));
    target
      ..store = store
      ..matrix.setFrom(matrix)
      ..frame = frame
      ..originX = _origin.x
      ..originY = _origin.y
      ..originZ = _origin.z;
  }

  _ViewHistory _viewCreated(_NodeStore store) {
    _allocations++;
    return _ViewHistory(store);
  }

  void _record(_NodeStore store, MeshNode node, int frame) {
    final key = _keyOf(node);
    final entry = store.nodes[node] ?? _created(store, node);
    entry.frame = frame;
    if (entry._key == key && _isAtOrigin(entry)) return;
    entry
      .._key = key
      .._originX = _origin.x
      .._originY = _origin.y
      .._originZ = _origin.z;
    _copies++;
    entry.world.setFrom(node.worldMatrix);

    if (node.skeleton case final skeleton?) {
      entry.joints = _copied(entry.joints, skeleton.matrices);
    }
    if (node.morph case final morph?) {
      entry.morphWeights = _copied(entry.morphWeights, morph.weights);
    }
    if (node is InstancedMeshNode) {
      final floats = node.count * InstancedMeshNode.floatsPerInstance;
      entry
        ..instances = _copied(
          entry.instances,
          Float32List.sublistView(node.instanceData, 0, floats),
        )
        ..instanceCount = node.count;
    }
  }

  bool _isAtOrigin(NodeHistory entry) =>
      entry._originX == _origin.x &&
      entry._originY == _origin.y &&
      entry._originZ == _origin.z;

  /// Moves [entry]'s world matrix into the current origin's space: the scene
  /// moved every node by `from - to`, so the past moves the same way. Joint
  /// palettes and instance bytes are relative to the node and do not move.
  void _rebase(NodeHistory entry) {
    if (_isAtOrigin(entry)) return;
    final dx = entry._originX - _origin.x;
    final dy = entry._originY - _origin.y;
    final dz = entry._originZ - _origin.z;
    final m = entry.world.storage;
    // `T(d) · W`: each column's w carries the translation in.
    for (var column = 0; column < 4; column++) {
      final w = m[column * 4 + 3];
      m[column * 4] += dx * w;
      m[column * 4 + 1] += dy * w;
      m[column * 4 + 2] += dz * w;
    }
    entry
      .._originX = _origin.x
      .._originY = _origin.y
      .._originZ = _origin.z;
  }

  NodeHistory _created(_NodeStore store, MeshNode node) {
    _allocations++;
    return store.nodes[node] = NodeHistory._();
  }

  /// [source] copied into [into], which is reused when it is the right length
  /// and replaced when it is not.
  Float32List _copied(Float32List? into, List<double> source) {
    final target = into != null && into.length == source.length
        ? into
        : _grown(source.length);
    for (var i = 0; i < source.length; i++) {
      target[i] = source[i];
    }
    return target;
  }

  Float32List _grown(int length) {
    _allocations++;
    return Float32List(length);
  }

  static (int, int, int, int) _keyOf(MeshNode node) => (
    node.worldVersion,
    node.skeleton?.poseVersion ?? 0,
    node.morph?.version ?? 0,
    node is InstancedMeshNode ? node.dataVersion : 0,
  );
}

/// What the renderer does to a history that a caller cannot. Not exported by
/// `flutter3d_core.dart`.
extension FrameHistoryInternals on FrameHistory {
  /// Hands what [from] was drawn with to [to], which answers [viewProjection]
  /// and [of] with it from now on, and [from] with nothing: a view made
  /// afresh each frame for the same camera carries on the last one's past
  /// rather than having none, and the two never share one.
  void carryView(RenderView from, RenderView to) {
    final entry = _views[from];
    if (entry == null || _views[to] != null) return;
    _views[from] = null;
    _views[to] = entry;
    // The same entries, owned by the view that carries them on.
    if (identical(entry.store.owner, from)) entry.store.owner = to;
  }

  /// Forgets [view]'s past: what the renderer calls when it gives up the
  /// view's state after the view went undrawn for a while.
  void forgetView(RenderView view) => _views[view] = null;

  /// The scene origin of the frame about to be drawn. The renderer's to set
  /// before any pass reads this history.
  set origin(WorldPosition origin) => _origin = origin;
}
