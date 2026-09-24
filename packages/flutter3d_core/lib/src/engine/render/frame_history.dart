/// What the previous frame looked like, for effects that need to know — `G2`.
///
/// A temporal resolve reprojects last frame's picture, and motion blur and
/// the velocity it needs are both "where was this a frame ago". Neither can
/// be answered from the scene, which only knows where things are now, so the
/// renderer keeps a copy of the few things that move: each mesh's world
/// matrix, its joint palette, its morph weights and its instance bytes, and
/// each view's unjittered view-projection.
///
/// **Copied only when something changed.** A node's change key is the
/// versions the scene already keeps — its world, its skeleton's pose, its
/// morph, its instance data — and a node whose key has not moved since the
/// last copy is not copied again. So a still scene costs a lookup a node and
/// allocates nothing after the first frame, which [allocations] counts.
///
/// Off until something asks: [tracking] is false on a renderer whose frames
/// have nothing temporal in them, and the renderer skips the walk entirely.
library;

import 'dart:typed_data';

import 'package:vector_math/vector_math.dart' as vm;

import '../scene/camera_node.dart';
import '../scene/instanced_mesh_node.dart';
import '../scene/mesh_node.dart';

/// One node as it was at the end of the last frame it was recorded in.
final class NodeHistory {
  NodeHistory._();

  /// The world matrix.
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
}

final class _ViewHistory {
  final vm.Matrix4 matrix = vm.Matrix4.zero();
  int frame = -1;
}

final class FrameHistory {
  /// Whether the renderer records a history at all. Set by whatever needs
  /// one; nothing in 0.8.0's defaults does.
  bool tracking = false;

  final Expando<NodeHistory> _nodes = Expando<NodeHistory>('frame history');
  final Expando<_ViewHistory> _views = Expando<_ViewHistory>('view history');
  int _lastFrame = -1;

  /// Buffers this history has created, for tests: an entry, a palette, a set
  /// of weights, an instance copy or a view matrix, each counted once when it
  /// is made or has to grow.
  int get allocations => _allocations;
  int _allocations = 0;

  /// Nodes copied, for tests: a node whose key did not move is not.
  int get copies => _copies;
  int _copies = 0;

  /// [node] as it was at the end of the last recorded frame, or null when it
  /// has not been recorded yet — a node that has just appeared has no past,
  /// and an effect treats it as standing still.
  NodeHistory? of(MeshNode node) => _nodes[node];

  /// Whether [node] has changed since it was last recorded. False for a node
  /// never recorded, for the same reason [of] is null for one.
  bool moved(MeshNode node) {
    final entry = _nodes[node];
    return entry != null && entry._key != _keyOf(node);
  }

  /// The unjittered view-projection [camera] was drawn with at the end of the
  /// last recorded frame, or null when that frame had no view through it.
  ///
  /// By camera rather than by the view's place in a list, because the list
  /// is the caller's and may be reordered between frames; a camera is the
  /// thing whose motion a velocity measures. The matrix is the camera's own
  /// ([CameraNode.viewProjection]), before any backend's depth range or
  /// framebuffer origin, so a reader adjusts it the way it adjusts the
  /// current one.
  vm.Matrix4? viewProjection(CameraNode camera) {
    final entry = _views[camera];
    return entry != null && entry.frame == _lastFrame ? entry.matrix : null;
  }

  /// Records every node in [meshes] and every camera in [views] with the
  /// matrix it drew with, as frame [frame]. The renderer's to call, once,
  /// when a frame is done.
  void endFrame({
    required int frame,
    required Iterable<MeshNode> meshes,
    required Iterable<(CameraNode, vm.Matrix4)> views,
  }) {
    for (final node in meshes) {
      _record(node, frame);
    }
    for (final (camera, matrix) in views) {
      (_views[camera] ??= _viewCreated())
        ..matrix.setFrom(matrix)
        ..frame = frame;
    }
    _lastFrame = frame;
  }

  _ViewHistory _viewCreated() {
    _allocations++;
    return _ViewHistory();
  }

  void _record(MeshNode node, int frame) {
    final key = _keyOf(node);
    final entry = _nodes[node] ?? _created(node);
    entry.frame = frame;
    if (entry._key == key) return;
    entry._key = key;
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

  NodeHistory _created(MeshNode node) {
    _allocations++;
    return _nodes[node] = NodeHistory._();
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
