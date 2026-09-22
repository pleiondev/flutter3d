import 'package:flutter3d/flutter3d.dart' hide Material;
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:vector_math/vector_math.dart' show Vector3;

import '../diagnostics/issues.dart';

/// `edu-07b`: the path `edu-07a`'s own doc comment names as the one `prop`
/// does not close — a real glTF/`.f3d` asset, loaded the way every other
/// modelled thing in this repo already loads one
/// (`decodeModelInIsolate` + `ModelAsset.fromDocument`, `fixture_visuals.dart`'s
/// own `_load`), rather than a box or a cylinder standing in for it.
///
/// **A `model` entity, not a second `PropVisuals`.** `doc/edu-00-interactive-format.md`
/// §6 and §11 already settle the shape: `{"type": "model", "name": "engine-body",
/// "at": [...], "asset": "assets/models/engine.f3d"}`. What changes between a
/// `prop` and this is not the entity's own contract — a name, a position, a
/// yaw — but what backs it: one procedural [MeshNode] there, a whole decoded
/// hierarchy of them here, most of them themselves named
/// (`ModelNode.name`) and therefore addressable a level layer deeper than a
/// `prop` ever needs to be — `"engine-body#valve_cover"`, not just
/// `"engine-body"`.
final class ModelVisuals {
  ModelVisuals(
    this.scene, {
    required this.device,
    AssetSource Function(String path)? source,
    IssueSink? onIssue,
  }) : _source = source ?? BundleAssetSource.new,
       onIssue = onIssue ?? printIssue;

  final Scene scene;
  final GraphicsDevice device;
  final IssueSink onIssue;

  /// How a `model` entity's `asset` path becomes something [decodeModelInIsolate]
  /// can read. [BundleAssetSource] by default — the same source every
  /// shipping level in this repo loads a model through — swappable so a test
  /// can hand it [FileAssetSource] and read a real fixture off disk without
  /// faking Flutter's asset bundle.
  final AssetSource Function(String path) _source;

  static const String entityType = 'model';

  final List<ModelAsset> _assets = <ModelAsset>[];
  final List<ModelInstance> _instances = <ModelInstance>[];

  /// Every root this built, by [EntityDef.name] — what `applyLessonStepToCamera`'s
  /// `nodes` map already reaches a `prop` through, extended one level: a
  /// key of `"entity#node"` reaches a *named node inside* that entity's own
  /// model, for `offsets`/`attachTo` paths §6 of the format spells as
  /// `"engine-body#valve_cover"`.
  final Map<String, SceneNode> _nodes = <String, SceneNode>{};

  Map<String, SceneNode> get nodes =>
      Map<String, SceneNode>.unmodifiable(_nodes);

  /// Where each root stood as authored, the same contract [PropVisuals.restPositions]
  /// already keeps — built from the root only: a sub-node's rest pose is
  /// already carried by the model itself (`ModelNode.translation`), which is
  /// what an absent `offsets` entry for it already means.
  Map<String, Vector3> get restPositions => <String, Vector3>{
    for (final entry in _nodes.entries) entry.key: entry.value.readPosition(),
  };

  /// Decodes and instantiates [entity]'s `asset` if it names a `model`; null
  /// and no effect otherwise, [PropVisuals.add]'s own "not every entity is
  /// mine" contract. Awaited by the caller, not fired and forgotten the way
  /// `FixtureVisuals._addModel` is — a lesson's steps read a node's rest
  /// position the moment the level opens, so the model has to already be in
  /// the scene by the time [LevelReady]/[LessonReady] is emitted, not two
  /// frames later.
  Future<SceneNode?> add(EntityDef entity) async {
    if (entity.type != entityType) return null;

    final path = entity.string('asset');
    if (path == null) {
      onIssue(Issue('$entityType "${entity.name ?? '?'}" names no asset'));
      return null;
    }

    final ModelAsset asset;
    try {
      final document = await decodeModelInIsolate(
        ModelLoadRequest(source: _source(path)),
      );
      asset = await ModelAsset.fromDocument(
        document,
        device: device,
        name: path,
      );
    } catch (error) {
      onIssue(
        Issue(
          '$entityType "${entity.name ?? '?'}" could not load "$path": $error',
        ),
      );
      return null;
    }
    _assets.add(asset);

    final instance = asset.instantiate(scene, name: entity.name);
    instance.root.setPositionFrom(entity.position);
    instance.root.setRotationYawPitchRoll(entity.yaw, 0.0, 0.0);
    _instances.add(instance);

    final entityName = entity.name;
    if (entityName != null) {
      _nodes[entityName] = instance.root;
      for (var i = 0; i < asset.nodes.length; i++) {
        final nodeName = asset.nodes[i].name;
        if (nodeName != null) {
          _nodes['$entityName#$nodeName'] = instance.nodes[i];
        }
      }
    }
    return instance.root;
  }

  /// Takes every model this built out of the scene and releases its
  /// uploads — [FixtureVisuals.dispose]'s own contract for the models it
  /// caches, kept here for the ones this class owns outright rather than
  /// shares.
  void dispose() {
    for (final instance in _instances) {
      instance.removeFromScene();
    }
    for (final asset in _assets) {
      asset.release(device);
    }
    _instances.clear();
    _assets.clear();
    _nodes.clear();
  }
}
