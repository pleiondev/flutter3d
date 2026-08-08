import 'package:vector_math/vector_math.dart';

import 'camera_node.dart';
import 'light_node.dart';
import 'mesh_node.dart';
import 'scene_node.dart';

/// A scene: a hierarchy of nodes plus flat registries of what is in it.
///
/// The hierarchy is what users author against. The registries are what the
/// renderer iterates.
///
/// Keeping both is deliberate, and it is what Babylon does too (`scene.meshes`
/// alongside the node tree). Choosing a classic inheritance tree does not oblige
/// anyone to walk that tree every frame: registries are maintained on attach and
/// detach, so per-frame culling is a linear pass over a contiguous list. In Dart
/// that difference matters more than in JS, because a tree walk with a callback
/// per node is exactly the shape that produces GC pressure inside the frame
/// budget.
final class Scene {
  Scene({String? name}) : root = SceneNode(name: name ?? 'root') {
    // The root belongs to this scene from the start, so anything added below it
    // registers itself immediately.
    root.bindToScene(this);
  }

  final SceneNode root;

  final List<MeshNode> _meshes = <MeshNode>[];
  final List<LightNode> _lights = <LightNode>[];
  final List<CameraNode> _cameras = <CameraNode>[];

  /// Everything drawable currently in the scene, in attachment order.
  List<MeshNode> get meshes => _meshes;

  List<LightNode> get lights => _lights;

  List<CameraNode> get cameras => _cameras;

  /// Ambient light applied where no direct light reaches. A placeholder for
  /// image-based lighting, which needs mip levels flutter_gpu does not have yet.
  double ambientIntensity = 0.06;

  Vector3 ambientColor = Vector3(1.0, 1.0, 1.0);

  /// Convenience for the common case of one node under the root.
  T add<T extends SceneNode>(T node) {
    root.add(node);
    return node;
  }

  void remove(SceneNode node) => node.removeFromParent();

  void registerMesh(MeshNode node) => _meshes.add(node);

  void unregisterMesh(MeshNode node) => _meshes.remove(node);

  void registerLight(LightNode node) => _lights.add(node);

  void unregisterLight(LightNode node) => _lights.remove(node);

  void registerCamera(CameraNode node) => _cameras.add(node);

  void unregisterCamera(CameraNode node) => _cameras.remove(node);

  /// First light of the given type, or null.
  ///
  /// The renderer currently shades with a single directional light: more than
  /// one needs either an uber-shader loop or clustered lighting, and both are
  /// shader work rather than scene work.
  LightNode? firstLightOfType(LightType type) {
    for (var i = 0; i < _lights.length; i++) {
      if (_lights[i].type == type) return _lights[i];
    }
    return null;
  }

  /// World-space bounds of every visible mesh, for framing a camera.
  Aabb3 computeBounds({bool visibleOnly = true}) {
    var minX = double.infinity, minY = double.infinity, minZ = double.infinity;
    var maxX = -double.infinity,
        maxY = -double.infinity,
        maxZ = -double.infinity;
    var any = false;

    for (var i = 0; i < _meshes.length; i++) {
      final node = _meshes[i];
      if (visibleOnly && !node.visibleInHierarchy) continue;
      final bounds = node.worldBounds;
      any = true;
      if (bounds.min.x < minX) minX = bounds.min.x;
      if (bounds.min.y < minY) minY = bounds.min.y;
      if (bounds.min.z < minZ) minZ = bounds.min.z;
      if (bounds.max.x > maxX) maxX = bounds.max.x;
      if (bounds.max.y > maxY) maxY = bounds.max.y;
      if (bounds.max.z > maxZ) maxZ = bounds.max.z;
    }

    if (!any) return Aabb3();
    return Aabb3.minMax(Vector3(minX, minY, minZ), Vector3(maxX, maxY, maxZ));
  }

  @override
  String toString() => 'Scene(${_meshes.length} meshes, ${_lights.length} '
      'lights, ${_cameras.length} cameras)';
}
