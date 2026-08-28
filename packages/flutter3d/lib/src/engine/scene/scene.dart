import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:vector_math/vector_math.dart';

import 'camera_node.dart';
import 'light_node.dart';
import 'lod_group.dart';
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

  /// Level-of-detail groups, so something can drive their selection.
  ///
  /// A flat registry like the others, and for the same reason: the renderer
  /// has to visit every one of these each frame, and walking the tree to find
  /// them would make the cost of a LOD proportional to the size of the scene
  /// rather than to the number of LODs.
  final List<LodGroup> _lodGroups = <LodGroup>[];

  /// Everything drawable currently in the scene, in attachment order.
  List<MeshNode> get meshes => _meshes;

  List<LightNode> get lights => _lights;

  List<CameraNode> get cameras => _cameras;

  List<LodGroup> get lodGroups => _lodGroups;

  /// Ambient light applied where no direct light reaches.
  ///
  /// The flat stand-in for [environment], used when a scene has none. It also
  /// scales the environment when there is one, so the same knob dials indirect
  /// light either way and the two are alternatives rather than a sum.
  double ambientIntensity = 0.06;

  Vector3 ambientColor = Vector3(1.0, 1.0, 1.0);

  /// A prefiltered environment cube: what a physical surface reflects.
  ///
  /// Its levels are the roughness scale — level zero is a mirror, the last is
  /// rough enough to stand in for irradiance — so it must be built with
  /// [EnvironmentMap.prefilter] and uploaded with the resulting chain. A cube
  /// with no levels reflects the same sharp image at every roughness, which
  /// reads as every surface being polished.
  ///
  /// Null leaves the flat [ambientIntensity] doing the work, which is what
  /// every scene did before this existed and what all of them still do until
  /// they are given one.
  TextureHandle? environment;

  /// How many levels [environment] has below its base.
  ///
  /// Handed to the shader as the roughness scale and as the "is there one"
  /// flag in a single number. Kept beside the texture rather than read off it
  /// because a [TextureHandle] does not carry its level count, and a renderer
  /// that guessed would guess wrong on the one cube that matters.
  int environmentLevels = 0;

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

  void registerLodGroup(LodGroup node) => _lodGroups.add(node);

  void unregisterLodGroup(LodGroup node) => _lodGroups.remove(node);

  /// First light of the given type, or null.
  ///
  /// A convenience for scene code — "where is the key light" — not something the
  /// renderer needs: it packs every visible light into a [LightBuffer] and the
  /// shaders loop over the lot.
  LightNode? firstLightOfType(LightType type) {
    for (var i = 0; i < _lights.length; i++) {
      if (_lights[i].type == type) return _lights[i];
    }
    return null;
  }

  /// World-space bounds of every visible mesh, for framing a camera.
  ///
  /// [castersOnly] narrows it to meshes that actually cast a shadow, which is
  /// what the shadow pass wants and what "the size of the scene" means to it.
  /// The two are not the same question and used to be answered by the same
  /// call: a mesh marked `castsShadow = false` is invisible to the shadow pass
  /// but was still enlarging the volume that pass is fitted to. One sky dome
  /// round the camera — a kilometre of nothing that casts nothing — would
  /// coarsen every distant shadow in the level, because the last cascade covers
  /// the whole scene and its texel size is that radius over the resolution.
  Aabb3 computeBounds({bool visibleOnly = true, bool castersOnly = false}) {
    var minX = double.infinity, minY = double.infinity, minZ = double.infinity;
    var maxX = -double.infinity,
        maxY = -double.infinity,
        maxZ = -double.infinity;
    var any = false;

    for (var i = 0; i < _meshes.length; i++) {
      final node = _meshes[i];
      if (visibleOnly && !node.visibleInHierarchy) continue;
      if (castersOnly && !node.castsShadow) continue;
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
  String toString() =>
      'Scene(${_meshes.length} meshes, ${_lights.length} '
      'lights, ${_cameras.length} cameras)';
}
