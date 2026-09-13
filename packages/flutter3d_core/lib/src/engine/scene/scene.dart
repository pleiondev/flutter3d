import 'dart:collection';

import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:vector_math/vector_math.dart';

import 'camera_node.dart';
import 'light_node.dart';
import 'lod_group.dart';
import 'mesh_node.dart';
import 'reflection_probe_node.dart';
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

  /// How many times something asked for the static shadow atlas to be drawn
  /// again, which is what a renderer compares against its own last bake.
  ///
  /// A counter rather than a flag: the renderer holds two atlases and a bake it
  /// may skip entirely, so "has this been dealt with" is a question only the
  /// renderer can answer, and a flag it forgot to clear would bake for ever
  /// while a flag it cleared too early would bake never.
  int get staticShadowGeneration => _staticShadowGeneration;
  int _staticShadowGeneration = 0;

  /// Says the static half of the cube atlas no longer matches the scene.
  ///
  /// Called by a static caster that changed how it casts. The pixels it put in
  /// that atlas were drawn once and are kept for as long as the atlas rows stay
  /// with the same lights, so nothing else in a frame would notice.
  void invalidateStaticShadows() => _staticShadowGeneration++;

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

  /// Reflection probes, in attachment order.
  ///
  /// A registry for the same reason the lights are one: the renderer gives
  /// each of these a pass every frame, and a mesh picks the nearest of them
  /// per draw, so both want a list rather than a tree walk.
  final List<ReflectionProbeNode> _probes = <ReflectionProbeNode>[];

  /// Everything drawable currently in the scene, in attachment order.
  ///
  /// **A view, where these four used to be the lists themselves.** Handing out
  /// the renderer's own culling registry means any caller can empty it, and a
  /// registry emptied behind the tree's back desynchronises the two with
  /// nothing to notice: the nodes are still attached, still have parents, and
  /// are simply never drawn again. A view costs nothing — it is not a copy —
  /// and turns that into a throw at the call site that did it.
  ///
  /// Built once each rather than per call, for the reason `MechanismWorld.all`
  /// gives about itself: the renderer reads these every frame.
  List<MeshNode> get meshes => _meshesView;
  late final List<MeshNode> _meshesView = UnmodifiableListView<MeshNode>(
    _meshes,
  );

  List<LightNode> get lights => _lightsView;
  late final List<LightNode> _lightsView = UnmodifiableListView<LightNode>(
    _lights,
  );

  List<CameraNode> get cameras => _camerasView;
  late final List<CameraNode> _camerasView = UnmodifiableListView<CameraNode>(
    _cameras,
  );

  List<LodGroup> get lodGroups => _lodGroupsView;
  late final List<LodGroup> _lodGroupsView = UnmodifiableListView<LodGroup>(
    _lodGroups,
  );

  List<ReflectionProbeNode> get probes => _probesView;
  late final List<ReflectionProbeNode> _probesView =
      UnmodifiableListView<ReflectionProbeNode>(_probes);

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

  /// Detaches everything under the root and empties the registries.
  ///
  /// **There was no supported way to tear a scene down**, which is what made a
  /// level change leak: the caller could detach nodes one at a time, and each
  /// `unregisterMesh` is a linear scan, so emptying a scene of N meshes cost
  /// N² — on a renderer whose own benchmarks go to 200 000 objects. Emptying
  /// the registries once is linear in what is in them.
  ///
  /// The nodes are detached as well as forgotten, so anything still holding
  /// one gets a node with no parent and no scene rather than one that believes
  /// it is still in a scene that has moved on.
  ///
  /// It does not touch the GPU. Meshes, materials and textures belong to
  /// whatever loaded them — see `ResourceCache` — and a scene that freed them
  /// would free them out from under the next level that shares one.
  void clear() {
    for (final child in root.childrenView.toList(growable: false)) {
      child.removeFromParent();
    }
    _meshes.clear();
    _lights.clear();
    _cameras.clear();
    _lodGroups.clear();
    _probes.clear();
  }

  void registerMesh(MeshNode node) => _meshes.add(node);

  void unregisterMesh(MeshNode node) => _meshes.remove(node);

  void registerLight(LightNode node) => _lights.add(node);

  void unregisterLight(LightNode node) => _lights.remove(node);

  void registerCamera(CameraNode node) => _cameras.add(node);

  void unregisterCamera(CameraNode node) => _cameras.remove(node);

  void registerLodGroup(LodGroup node) => _lodGroups.add(node);

  void unregisterLodGroup(LodGroup node) => _lodGroups.remove(node);

  void registerProbe(ReflectionProbeNode node) => _probes.add(node);

  void unregisterProbe(ReflectionProbeNode node) => _probes.remove(node);

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
