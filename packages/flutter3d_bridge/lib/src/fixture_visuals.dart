import 'dart:async';

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:vector_math/vector_math.dart';

import 'fixture_appearance.dart';
import 'level_loader.dart';
import 'shared_meshes.dart';

export 'fixture_appearance.dart';

/// What the doors, lifts, platforms, buttons, keys and lights look like.
///
/// The simulation reports a [Fixture] — a box, a size, a material name and
/// whatever runs it — and this turns each one into a node and keeps that node
/// where the collider is. The simulation never learns that meshes exist, and
/// this never learns what the game's fixtures are called: the shapes come from
/// a [FixtureAppearance].
final class FixtureVisuals {
  FixtureVisuals(
    this.scene,
    this.level, {
    required this.appearance,
    required this.device,
    IssueSink? onIssue,
  }) : meshes = SharedMeshes(device),
       onIssue = onIssue ?? printIssue;

  /// The backend everything here uploads through.
  final GraphicsDevice device;

  /// Where this says what it could not draw — a door's model that would not
  /// load, which leaves a box where a door should be.
  final IssueSink onIssue;

  final Scene scene;

  /// The loaded level, for its palette and its already-uploaded maps: a door
  /// authored as `stone` should be the same stone as the wall it sits in, down
  /// to sharing the texture object rather than a second copy of the file.
  final LoadedLevel level;

  /// The game's half: silhouettes and fallback colours.
  final FixtureAppearance appearance;

  final List<_Piece> _pieces = <_Piece>[];

  /// Models already read off disk, by asset path.
  ///
  /// Ten torches sharing one model should be one decode and one upload. The
  /// cache is per-level for the same reason the texture cache is: a GPU
  /// resource outliving the level that owns it is a leak nobody notices.
  final Map<String, Future<ModelAsset?>> _models =
      <String, Future<ModelAsset?>>{};

  /// The level's lights, by name, so a fixture can dim the one it owns.
  final Map<String, LightNode> _lights = <String, LightNode>{};

  /// Materials whose emissive is driven every frame. Kept per fixture rather
  /// than shared, because two torches at different points of their flicker
  /// cannot be one material.
  final Map<LightFixture, Material> _glowing = <LightFixture, Material>{};

  /// One uploaded mesh per distinct shape, shared with the game's silhouettes.
  final SharedMeshes meshes;

  /// Learns where the level's named lights are. Called once, after the scene
  /// is built.
  void bindLights() {
    for (final node in scene.lights) {
      final name = node.name;
      if (name != null) _lights[name] = node;
    }
    for (final node in scene.lights) {
      _baseIntensity[node] = node.intensity;
    }
  }

  final Map<LightNode, double> _baseIntensity = <LightNode, double>{};

  void add(Fixture fixture) {
    final mechanism = fixture.mechanism;
    if (mechanism is LightFixture) {
      _addLightFixture(fixture, mechanism);
      return;
    }

    final model = fixture.entity.string('model');
    if (model != null) {
      // Asynchronous, and deliberately not awaited: a level with twenty props
      // should not load them one after another, and a key that appears two
      // frames late is a key nobody saw appear.
      unawaited(_addModel(fixture, model));
      return;
    }

    final source =
        level.level.materials[fixture.material] ??
        appearance.fallbackFor(fixture);
    final node = MeshNode(
      meshes.box(fixture.size),
      LevelLoader.materialFrom(
        source,
        level.materialTextures,
        name: fixture.material,
        tiling: LevelLoader.tilingSamplerFor(device),
      ),
      name: fixture.entity.name ?? fixture.entity.type,
    )..setPositionFrom(fixture.position);
    _tint(node.material, fixture);
    scene.add(node);
    _pieces.add(_Piece(fixture, node));
  }

  /// Places a light fixture, wires its glow to the simulation, and asks the
  /// game what it looks like.
  ///
  /// The glow material is built here rather than by the game because it is the
  /// thing [sync] drives: emissive strength and the light's intensity move
  /// together off one brightness number, and a torch whose flame stays bright
  /// while its light dims is a torch nobody believes.
  void _addLightFixture(Fixture fixture, LightFixture mechanism) {
    // Warm, because a light fixture the level said nothing about is a fire far
    // more often than it is anything else.
    final colour = fixture.entity.vector('color') ?? Vector3(1.0, 0.72, 0.36);

    final glow = Material(
      name: '${fixture.entity.type} glow',
      baseColor: Vector4(colour.x * 0.4, colour.y * 0.4, colour.z * 0.4, 1.0),
      roughness: 0.9,
      // The light itself is a scene light; this is only the thing that looks
      // hot. Emissive rather than a bright base colour, so the bloom picks it
      // up — an unbloomed flame reads as a painted orange square.
      emissive: Vector3(colour.x, colour.y, colour.z),
      emissiveStrength: fixture.entity.number('glow') ?? 3.0,
    );
    _glowing[mechanism] = glow;
    _baseGlow[mechanism] = glow.emissiveStrength;

    final holder = SceneNode(name: fixture.entity.type)
      ..setPositionFrom(fixture.position)
      ..setRotation(
        Quaternion.axisAngle(Vector3(0.0, 1.0, 0.0), fixture.entity.yaw),
      );
    scene.add(holder);

    final fire = appearance.buildLightFixture(
      LightFixtureBuild(
        fixture: fixture,
        mechanism: mechanism,
        holder: holder,
        glow: glow,
        meshes: meshes,
      ),
    );
    // No mesh for the flame: it is particles, and where they come from is a
    // node's world position read every frame.
    if (fire != null) _flames[mechanism] = fire;

    // **A light fixture does not shadow its own light.**
    //
    // What it looked like when it did: a black pyramid down the wall under
    // every torch, with a dark apron on the floor in front of it. That is not a
    // bug in the shadow pass — it is the pass being right about a scene that is
    // wrong. A torch's light sits about a third of a metre out from the wall
    // and its bracket, shaft and cup hang in that same space, so the fixture
    // occludes a point source at arm's length and throws a shadow the size of
    // the room's whole lit area. The nearer a blocker is to a point light, the
    // bigger its shadow; nothing is nearer to this one than the thing holding
    // it.
    //
    // A real torch does not do this because its flame is not a point in front
    // of the cup — it is a volume around and above one, and it lights the
    // bracket from every side at once. A single point light cannot be that, and
    // the cheap, standard answer is the one taken here: the fixture is lit and
    // does not cast.
    //
    // Opt back in with `castsShadow: true` on the entity, for a fixture whose
    // shade is the point — a lamp meant to throw a pattern on the ceiling. The
    // default is off because the common case is a light that should not carve a
    // hole out of what it lights.
    if (!fixture.entity.flag('castsShadow')) {
      holder.traverse((SceneNode node) {
        if (node is MeshNode) node.castsShadow = false;
      });
    }

    _pieces.add(_Piece(fixture, holder));
  }

  /// The fire of each torch: where it comes out, and what it is worth.
  final Map<LightFixture, TorchFire> _flames = <LightFixture, TorchFire>{};

  /// Every fixture that wants particles.
  Map<LightFixture, TorchFire> get flames => _flames;

  /// Multiplies the entity's own tint into the material's base colour.
  ///
  /// This is what lets three keys share one model and one set of maps and
  /// still be a red key, a blue key and an iron one. The tint is a multiplier
  /// rather than a replacement, so the metal keeps its own scratches and
  /// shading — a flat recolour would look like a sticker.
  ///
  /// A material built per fixture rather than shared, because two keys with
  /// different tints cannot be the same Material object; the textures inside
  /// it are still shared, which is where the memory actually is.
  void _tint(Material material, Fixture fixture) {
    final tint = fixture.entity.vector('tint');
    if (tint == null) return;
    material.baseColor.multiply(Vector4(tint.x, tint.y, tint.z, 1.0));
  }

  /// Puts a modelled fixture in the scene once its file has been read.
  Future<void> _addModel(Fixture fixture, String path) async {
    final generation = _generation;
    final asset = await _models.putIfAbsent(path, () => _load(path));
    // The level changed while the file was being read. The same race
    // `ActorVisuals._dress` guards against, met here later: a torch's model
    // arriving after `dispose` instantiated into a scene nobody draws and put
    // a row back in a list that had just been cleared.
    if (asset == null || generation != _generation) return;

    final instance = asset.instantiate(scene);

    // The model's own material is replaced by the level's, so a key and the
    // lock it opens are described in one place — the level document — rather
    // than half in the document and half inside a binary somebody exported.
    final source = level.level.materials[fixture.material];
    if (source != null && source.hasMaps) {
      final material = LevelLoader.materialFrom(
        source,
        level.materialTextures,
        name: fixture.material,
        tiling: LevelLoader.tilingSamplerFor(device),
      );
      _tint(material, fixture);
      for (final node in instance.nodes) {
        if (node is MeshNode) node.material = material;
      }
    }

    instance.root.setPositionFrom(fixture.position);
    _pieces.add(_Piece(fixture, instance.root));
  }

  Future<ModelAsset?> _load(String path) async {
    try {
      final document = await decodeModelInIsolate(
        ModelLoadRequest(source: BundleAssetSource(path)),
      );
      // `await`, not a bare return: this returns a future, and a future
      // returned out of a `try` completes after the block has been left, so
      // the `catch` below never saw its failures. A model whose upload threw
      // took the whole level down instead of printing the line under this.
      // The 3.47 analyser is what noticed; it had been true all along.
      return await ModelAsset.fromDocument(
        document,
        device: device,
        name: path,
      );
    } catch (error) {
      onIssue('level: could not load model "$path": $error');
      return null;
    }
  }

  /// Emissive strength at full brightness, remembered per fixture so a level
  /// can set one window brighter than another.
  final Map<LightFixture, double> _baseGlow = <LightFixture, double>{};

  /// Moves every node to its collider, once a frame.
  ///
  /// Reading the collider rather than the mover's progress means a door that
  /// stopped because somebody was standing in it is drawn where it actually
  /// stopped, and there is no second copy of the travel arithmetic to disagree
  /// with the first.
  void sync(double elapsed) {
    for (final piece in _pieces) {
      final mechanism = piece.fixture.mechanism;
      if (appearance.isSpent(piece.fixture)) {
        piece.node.visible = false;
        continue;
      }

      final scale = appearance.scaleOf(piece.fixture);
      if (scale <= 0.0) {
        piece.node.visible = false;
        continue;
      }
      piece.node
        ..visible = true
        ..setScale(scale, scale, scale);
      piece.node.setPositionFrom(piece.fixture.position);

      final material = piece.node is MeshNode
          ? (piece.node as MeshNode).material
          : null;
      if (material != null) appearance.refresh(piece.fixture, material);

      if (appearance.spins(piece.fixture)) {
        piece.node.setRotation(
          Quaternion.axisAngle(Vector3(0.0, 1.0, 0.0), elapsed * 1.4),
        );
      }

      // The flame and the light it casts move together, off one number. A
      // torch whose flame stays bright while its light dims is a torch nobody
      // believes.
      if (mechanism is LightFixture) {
        final brightness = mechanism.brightness;
        final glow = _glowing[mechanism];
        if (glow != null) {
          glow.emissiveStrength = (_baseGlow[mechanism] ?? 3.0) * brightness;
        }

        final name = mechanism.light;
        final node = name == null ? null : _lights[name];
        if (node != null) {
          node.intensity = (_baseIntensity[node] ?? 0.0) * brightness;
          // And where it is, not only how bright. The fire is measured from
          // its own particles, so the light sits where they currently are
          // rather than at the bracket on the wall. Null until something has
          // measured it, which is every fixture that is not a fire.
          final at = mechanism.measuredAt;
          if (at != null) node.setPositionFrom(at);
        }
      }
    }
  }

  /// Takes everything this built out of the scene and gives the meshes back.
  ///
  /// The counterpart to a class that only ever grew: every `add` put a node in
  /// the scene and a row in one of these maps, and a level change built the
  /// next level's on top of them. The doc on the model cache has said it is
  /// per level "for the same reason the texture cache is: a GPU resource
  /// outliving the level that owns it is a leak nobody notices" — and there
  /// was no way to say the level was over. `RunSession.close` is that moment.
  ///
  /// **The decoded models used to be deliberately kept**, on the claim that a
  /// `ModelAsset` was shared between levels through a cache keyed by path.
  /// There is no such cache — [_models] is this instance's own and dies with
  /// it — so keeping the entries only stranded the uploads, which is exactly
  /// the leak the cache's own doc warns about. Released through the future
  /// rather than its value, so a model still being read is released the
  /// moment it arrives; the generation bump keeps it out of the scene.
  void dispose() {
    _generation++;
    for (final piece in _pieces) {
      piece.node.removeFromParent();
    }
    _pieces.clear();
    _lights.clear();
    _baseIntensity.clear();
    _glowing.clear();
    _flames.clear();
    _baseGlow.clear();
    for (final pending in _models.values) {
      unawaited(pending.then((asset) => asset?.release(device)));
    }
    _models.clear();
    meshes.dispose();
  }

  /// Bumped by [dispose], so a model that arrives late can tell.
  int _generation = 0;
}

final class _Piece {
  _Piece(this.fixture, this.node);

  final Fixture fixture;
  final SceneNode node;
}
