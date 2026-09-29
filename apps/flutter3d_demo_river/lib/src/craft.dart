part of 'river_game.dart';

/// Which model plays which part.
enum Craft {
  player('assets/models/jet_player.glb', 2.3, floats: false),
  enemyJet('assets/models/jet_enemy.glb', 2.5, floats: false),
  helicopter('assets/models/helicopter.glb', 2.8, floats: false),
  tankerA('assets/models/tanker_a.glb', 3.7, floats: true),
  tankerB('assets/models/tanker_b.glb', 3.7, floats: true);

  const Craft(this.file, this.length, {required this.floats});

  final String file;

  /// Nose to tail once fitted, in metres: about the length of the hitbox
  /// it stands for, so what is drawn is what can be hit.
  final double length;

  /// Sits on the water rather than centred on its flying height.
  final bool floats;
}

/// The meshes and materials shared by everything of a kind, uploaded once.
///
/// **Every stand-in faces +Z, the way every model does.** The models this
/// game loads all happen to be built nose along +Z, so the primitives are
/// turned to match when they are made, and one rule turns either to face
/// where it is going: [TargetComponent.face], [JetComponent.bankTowards].
final class _Kit {
  _Kit(this.device)
    : playerJet = _upload(
        device,
        jetMesh(Vector4(0.9, 0.2, 0.15, 1.0), Vector4(0.95, 0.95, 0.9, 1.0)),
        math.pi,
      ),
      enemyJet = _upload(
        device,
        jetMesh(Vector4(0.25, 0.3, 0.55, 1.0), Vector4(0.6, 0.65, 0.75, 1.0)),
        math.pi,
      ),
      tanker = _upload(device, tankerMesh(), -math.pi / 2.0),
      helicopter = _upload(device, helicopterMesh(), -math.pi / 2.0),
      rotor = DeviceMesh.upload(device, rotorMesh()),
      depot = DeviceMesh.upload(device, depotMesh()),
      shot = DeviceMesh.upload(device, shotMesh()),
      shard = DeviceMesh.upload(device, shardMesh()),
      water = DeviceMesh.upload(device, waterMesh());

  final GraphicsDevice device;
  final DeviceMesh playerJet;
  final DeviceMesh enemyJet;
  final DeviceMesh tanker;
  final DeviceMesh helicopter;
  final DeviceMesh rotor;
  final DeviceMesh depot;
  final DeviceMesh shot;
  final DeviceMesh shard;
  final DeviceMesh water;

  /// White, so the vertex colours are the colours.
  final engine.Material painted = engine.Material(
    name: 'painted',
    baseColor: Vector4(1.0, 1.0, 1.0, 1.0),
    roughness: 0.8,
  );

  final engine.Material waterMaterial = engine.Material(
    name: 'water',
    baseColor: Vector4(0.02, 0.09, 0.26, 1.0),
    roughness: 0.15,
  );

  /// A shot: lit from inside, so it reads against the water and the land.
  final engine.Material glow = engine.Material(
    name: 'glow',
    baseColor: Vector4(1.0, 0.85, 0.4, 1.0),
    emissive: Vector3(1.0, 0.75, 0.3),
    emissiveStrength: 4.0,
  );

  /// A helicopter's bullet: red, so it reads as the enemy's and not a
  /// shot of the jet's own.
  final engine.Material tracer = engine.Material(
    name: 'tracer',
    baseColor: Vector4(1.0, 0.2, 0.15, 1.0),
    emissive: Vector3(1.0, 0.15, 0.1),
    emissiveStrength: 6.0,
  );

  /// A bridge's shield, while the level's task is not done.
  final engine.Material shield = engine.Material(
    name: 'shield',
    baseColor: Vector4(0.3, 0.95, 1.0, 1.0),
    emissive: Vector3(0.2, 0.9, 1.0),
    emissiveStrength: 5.0,
  );

  final engine.Material smoke = engine.Material(
    name: 'smoke',
    baseColor: Vector4(0.06, 0.06, 0.06, 1.0),
    roughness: 1.0,
  );

  final engine.Material spray = engine.Material(
    name: 'spray',
    baseColor: Vector4(0.85, 0.92, 1.0, 1.0),
    emissive: Vector3(0.3, 0.35, 0.4),
    roughness: 0.3,
  );

  /// A shard of an explosion. Its own, because a blast fades it.
  engine.Material fire() => engine.Material(
    name: 'fire',
    baseColor: Vector4(1.0, 0.55, 0.15, 1.0),
    emissive: Vector3(1.0, 0.45, 0.1),
    emissiveStrength: 5.0,
  );

  /// The models by the part they play, once [RiverGame.dressWithModels]
  /// has loaded them. A part missing here draws its primitive.
  final Map<Craft, ModelAsset> models = <Craft, ModelAsset>{};

  static DeviceMesh _upload(GraphicsDevice device, MeshData mesh, double yaw) =>
      DeviceMesh.upload(device, mesh.transformed(Matrix4.rotationY(yaw)));
}

/// The models, put on the bodies the game already moves.
///
/// **A component is bridged through a holder, never through its model.**
/// Every bridged node is an empty [SceneNode] holding a pivot, and the
/// pivot holds what is drawn. Until [dressWithModels] has loaded the files,
/// and always in the tests, which never load them, that is the primitive
/// from `models.dart`; when a model arrives it replaces the pivot's
/// children, and nothing that moves the holder notices. The pivot is what
/// turns a craft to face its way and banks the jet: the bridge writes the
/// holder's rotation from the Flame angle every frame, so anything turned
/// there would be turned straight back.
extension RiverGameCraft on RiverGame {
  /// Loads every model and dresses whatever is already in play. A target
  /// made later is dressed as it is made. A model that fails to load
  /// leaves its primitive, and the game plays on.
  ///
  /// [source] is the app bundle in the app; a test, which has no bundle an
  /// isolate can read, hands in the files on disk.
  Future<void> dressWithModels({
    AssetSource Function(String path) source = BundleAssetSource.new,
  }) async {
    for (final craft in Craft.values) {
      try {
        final document = await decodeModelInIsolate(
          ModelLoadRequest(source: source(craft.file)),
        );
        _kit.models[craft] = await ModelAsset.fromDocument(
          document,
          device: _device,
          name: craft.file,
        );
      } catch (error) {
        debugPrint('river: ${craft.file} did not load ($error)');
      }
    }
    for (final MapEntry(key: pivot, value: craft) in _dressed.entries) {
      _dress(pivot, craft);
    }
  }

  /// Puts [craft]'s model under [pivot] in place of whatever it held, fitted
  /// to [Craft.length] and centred on it. Nothing happens while that model
  /// has not loaded.
  void _dress(SceneNode pivot, Craft craft) {
    final asset = _kit.models[craft];
    if (asset == null) return;
    for (final child in pivot.children.toList()) {
      child.removeFromParent();
    }
    final instance = asset.instantiateFitted(
      _scene,
      length: craft.length,
      onGround: craft.floats,
      parent: pivot,
      name: '${pivot.name} model',
    );
    // A ship sits a little into the water, its keel under the surface.
    if (craft.floats) instance.root.translate(0.0, -0.15, 0.0);
  }
}
