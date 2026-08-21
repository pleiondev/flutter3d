import 'dart:async';

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter3d_particles/flutter3d_particles.dart';
import 'package:vector_math/vector_math.dart';

import 'level_loader.dart';
import 'shared_meshes.dart';

/// One torch's fire.
///
/// A [LightEmitter], so the particle system measures it — and the object the
/// emission is keyed on, which means the thing that burns and the thing that
/// is measured are the same thing rather than two that have to be kept in
/// step.
final class TorchFire with LightEmitter {
  TorchFire(this.origin, {this.rise = 0.0});

  /// The node the flame rises from, read every frame so the fire is wherever
  /// the mesh ended up.
  final SceneNode origin;

  /// How far above that node's own position the flame actually starts.
  ///
  /// A number rather than a second transform: the offset is "just clear of the
  /// rim", and the rim belongs to whoever modelled the fixture.
  final double rise;

  /// Where the fire is, in world space.
  ///
  /// From the node's own transform, so the flame is wherever the level's yaw
  /// put the thing holding it. Recomputing it from the yaw instead is a second
  /// copy of the placement and a second chance to put the fire inside the wall,
  /// which is what the first version did.
  Vector3 originInto(Vector3 out) {
    final world = origin.worldMatrix;
    out.setValues(world.entry(0, 3), world.entry(1, 3), world.entry(2, 3));
    return out..y += rise;
  }
}

/// Everything the bridge has already decided by the time a silhouette is built.
///
/// Handed to [FixtureAppearance.buildLightFixture] so the game can hang meshes
/// off a node that is already positioned, turned and in the scene, and use a
/// glow material that is already wired to the simulation's brightness.
final class LightFixtureBuild {
  LightFixtureBuild({
    required this.fixture,
    required this.mechanism,
    required this.holder,
    required this.glow,
    required this.meshes,
  });

  final Fixture fixture;
  final LightFixture mechanism;

  /// Already placed, already turned by the entity's yaw, already in the scene.
  /// Parent every part to this and think in local space.
  final SceneNode holder;

  /// Emissive, tinted by the entity's colour, and driven every frame by
  /// [LightFixture.brightness]. Use it for the parts that are supposed to look
  /// hot; anything else needs a material of the game's own.
  final Material glow;

  /// Shared with every other fixture in the level. Ask it for boxes and
  /// cylinders rather than uploading a mesh per torch.
  final SharedMeshes meshes;
}

/// The half of a fixture's look that only the game can know.
///
/// [FixtureVisuals] owns the mechanism — placement, caches, the model loader,
/// the material override, and driving the glow and the light off one brightness
/// number. What a torch actually looks like is not mechanism: it is the
/// difference between a torch and a lamp and a window, and it is decided here.
abstract interface class FixtureAppearance {
  /// Builds the visible parts of a light fixture under [LightFixtureBuild.holder].
  ///
  /// Returns the fire it produced, or null for a fixture that glows without
  /// burning — a window, a lamp behind glass.
  TorchFire? buildLightFixture(LightFixtureBuild build);

  /// Something visible for a fixture whose material the level did not name.
  ///
  /// A game that would rather see nothing can return a flat colour; a game with
  /// keys and buttons will want to tell them apart at a distance.
  LevelMaterial fallbackFor(Fixture fixture);

  /// Whether the fixture is used up and should not be drawn at all.
  ///
  /// This and [spins] used to be one line each of `mechanism is Pickup` in
  /// [FixtureVisuals.sync], which is how the bridge came to know what a pickup
  /// was. Both questions are about *this game's* furniture: a collected medkit
  /// disappears, a racing game's checkpoint does not, and neither fact is the
  /// renderer's or the simulation's to hold.
  bool isSpent(Fixture fixture);

  /// How big to draw a fixture right now, as a fraction of its size.
  ///
  /// One for almost everything. It exists because a collected coin that simply
  /// stops being drawn reads as a rendering glitch — the eye needs a moment to
  /// connect the sound to the thing that made it — and a shrink is the cheapest
  /// honest way to give it one.
  ///
  /// [isSpent] stays the question "is it gone", and a game that shrinks
  /// something answers *that* only once the shrink has finished. The two are
  /// separate so a fixture can be invisible without being over, and over
  /// without ever having shrunk.
  double scaleOf(Fixture fixture);

  /// Whether it turns on the spot.
  ///
  /// The oldest trick in the genre, and it works for the same reason it always
  /// did: a thing that moves in a still room is a thing the player walks over
  /// to. Still a decision about furniture rather than about drawing.
  bool spins(Fixture fixture);

  /// A chance to change how a fixture looks, once a frame.
  ///
  /// [fallbackFor] is asked once, when the node is built, which is right for
  /// "what colour is a key" and wrong for anything whose look depends on what
  /// has happened. A checkpoint is the case that forced this: it was built
  /// blue, turned green in the code and stayed blue on the screen, so the one
  /// thing it exists to tell the player — *you have got this far* — it never
  /// said.
  ///
  /// The material handed over belongs to this fixture alone, so changing it
  /// changes nothing else. Fixtures drawn from a loaded model are not offered,
  /// because their materials belong to the model and are shared with every
  /// other copy of it.
  void refresh(Fixture fixture, Material material);
}

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
  })  : meshes = SharedMeshes(device),
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
  final Map<String, Future<ModelAsset?>> _models = <String, Future<ModelAsset?>>{};

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

    final source = level.level.materials[fixture.material] ??
        appearance.fallbackFor(fixture);
    final node = MeshNode(
      meshes.box(fixture.size),
      LevelLoader.materialFrom(
        source,
        level.materialTextures,
        name: fixture.material,
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
    final asset = await _models.putIfAbsent(path, () => _load(path));
    if (asset == null) return;

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
}

final class _Piece {
  _Piece(this.fixture, this.node);

  final Fixture fixture;
  final SceneNode node;
}
