import 'package:flutter3d/flutter3d.dart' hide Material;
import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:vector_math/vector_math.dart' show Vector3;

import 'level_loader.dart';

/// `edu-07`'s answer to the gap `doc/tooling-plan.md` names: neither a brush
/// (batched by material, `configurator.json`'s own doc comment already says
/// there is "no way to address this one box in `scene.meshes`") nor a
/// `type: "model"` entity (not read by [LevelLoader] at all — that path
/// needs an isolate-safe glTF/`.f3d` decode, a separate, larger piece) gives
/// a level document one *named*, individually addressable piece of
/// geometry. A `prop` entity does: one primitive shape, one [MeshNode] of
/// its own, not merged into any batch — so it can be found by
/// [EntityDef.name] the same way a `widget_surface`'s own node already can,
/// and `applyLessonStepToCamera`'s `nodes`/`restPositions` can reach it.
///
/// **Not a substitute for a real model.** `ls-e-00`'s actual engine, with
/// real disassemblable parts, still wants `type: "model"` — a box or a
/// cylinder standing in for "the valve cover" is a placeholder a lesson
/// author would replace, not a finished asset. What this closes is narrower
/// and immediate: `ls-i-01`'s configurator retinting the product it shows,
/// and any lesson content that wants `offsets`/`visible`/`highlight` to
/// move or hide something real before a model pipeline exists to load.
final class PropVisuals {
  PropVisuals(this.scene, {required this.device, required this.level});

  final Scene scene;
  final GraphicsDevice device;
  final Level level;

  static const String entityType = 'prop';

  final Map<String, MeshNode> _nodes = <String, MeshNode>{};

  /// Every prop this built, named or not — what [dispose] actually walks to
  /// remove each from [scene]; [_nodes] only holds the named subset
  /// [applyLessonStepToCamera]'s maps can reach.
  final List<MeshNode> _allNodes = <MeshNode>[];

  /// The uploaded geometry for every prop this built, released by [dispose]
  /// — kept apart from [_allNodes] because [MeshNode.mesh] is typed as the
  /// opaque [MeshGeometry], not the [DeviceMesh] that can actually be given
  /// back to [device]; [LoadedLevel.brushMeshes] keeps the same pair of
  /// lists for the same reason.
  final List<DeviceMesh> _meshes = <DeviceMesh>[];

  /// Every prop this has built, by [EntityDef.name] — an unnamed prop is
  /// still drawn, just unreachable by [applyLessonStepToCamera]'s maps,
  /// the same way an unnamed brush already is.
  Map<String, SceneNode> get nodes =>
      Map<String, SceneNode>.unmodifiable(_nodes);

  /// Where each prop stood as authored — [applyLessonStepToCamera]'s own
  /// `restPositions`, built here rather than by a second pass over
  /// [Level.entities], since this is the one place that already reads a
  /// `prop`'s position on its way into the scene.
  Map<String, Vector3> get restPositions => <String, Vector3>{
    for (final entry in _nodes.entries) entry.key: entry.value.readPosition(),
  };

  /// Builds a [MeshNode] for [entity] if it names a `prop`; null and no
  /// effect otherwise, the same "not every entity is mine" contract
  /// [WidgetSurfaceVisuals.add] already keeps.
  MeshNode? add(EntityDef entity) {
    if (entity.type != entityType) return null;

    final shape = _shapeFor(entity);
    final materialName = entity.string('material');
    final levelMaterial = materialName == null
        ? LevelMaterial()
        : level.materials[materialName] ?? LevelMaterial();
    final material = LevelLoader.materialFrom(
      levelMaterial,
      const <String, TextureHandle?>{},
      name: entity.name,
    );

    final mesh = DeviceMesh.upload(device, shape.build());
    final node = MeshNode(mesh, material, name: entity.name)
      ..setPositionFrom(entity.position);
    node.setRotationYawPitchRoll(entity.yaw, 0.0, 0.0);

    scene.add(node);
    _meshes.add(mesh);
    _allNodes.add(node);
    final name = entity.name;
    if (name != null) _nodes[name] = node;
    return node;
  }

  /// Retints [name]'s prop to [materialName], read from [level]'s own
  /// materials — `ls-i-01`'s "an annotation changes the product's colour",
  /// which `configurator.json`'s own doc comment names as the thing a brush
  /// cannot do (no name, batched with every other brush of the same
  /// material). A prop has both: [MeshNode.material] is a plain mutable
  /// field, not composed with anything else's, so retinting one never
  /// touches another prop that happens to share the old material.
  ///
  /// Silently does nothing for a [name] this never built or a
  /// [materialName] [level] does not have — the same "a typo should not
  /// crash the lesson" choice [add] already makes for a missing material.
  void setMaterial(String name, String materialName) {
    final node = _nodes[name];
    final levelMaterial = level.materials[materialName];
    if (node == null || levelMaterial == null) return;
    node.material = LevelLoader.materialFrom(
      levelMaterial,
      const <String, TextureHandle?>{},
      name: materialName,
    );
  }

  /// A box unless [EntityDef.string]`('shape')` names another — the same
  /// "absent means the ordinary case" convention `edu-00`'s own optional
  /// fields already keep.
  Shape _shapeFor(EntityDef entity) {
    switch (entity.string('shape')) {
      case 'sphere':
        return SphereShape(radius: entity.number('radius') ?? 0.5);
      case 'cylinder':
        final radius = entity.number('radius') ?? 0.5;
        return CylinderShape(
          radiusTop: radius,
          radiusBottom: radius,
          height: entity.number('height') ?? 1.0,
        );
      case 'box':
      default:
        return CuboidShape(size: entity.vector('size') ?? Vector3.all(1.0));
    }
  }

  /// Takes every prop this built out of the scene and releases its
  /// geometry — [LoadedLevel.dispose]'s own two calls, once per prop,
  /// since a prop's mesh belongs to this class rather than to the level's
  /// own [LoadedLevel.brushMeshes].
  void dispose() {
    for (final node in _allNodes) {
      node.removeFromParent();
    }
    for (final mesh in _meshes) {
      device.releaseGeometry(mesh.vertices);
      device.releaseGeometry(mesh.indices);
    }
    _nodes.clear();
    _allNodes.clear();
    _meshes.clear();
  }
}
