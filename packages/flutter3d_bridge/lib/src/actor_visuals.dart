import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show debugPrint;

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:vector_math/vector_math.dart';

import 'shared_meshes.dart';

/// What a monster is made of, which is the one thing the bridge cannot know.
///
/// Called every frame with the monster's current state, so a game is free to
/// answer with a shared material per kind, a brightened one for a monster that
/// was just hit, or something built on the spot.
abstract interface class ActorAppearance {
  /// The material to draw [monster] with right now.
  Material materialFor(Actor actor);

  /// A key that two actors share exactly when they should share one capsule
  /// mesh. The game's own answer, because the engine has no idea what makes
  /// two of its actors the same kind of thing.
  String meshKeyFor(Actor actor);

  /// The model to draw [actor] as, or null to leave it a capsule.
  ///
  /// Per actor rather than per key, because two actors of the same kind can be
  /// drawn differently and nothing here should decide they cannot. Actors
  /// sharing a path share one loaded [ModelAsset]; each gets its own instance.
  ///
  /// **A null is a perfectly good answer.** A turret, a trigger volume and a
  /// director are actors too, and a capsule is what the placeholder has always
  /// been — this adds a door rather than closing one.
  String? modelFor(Actor actor);

  /// Which of the model's clips [actor] should be playing, best first.
  ///
  /// **A list rather than a name, and the models are why.** These are
  /// third-party exports and they do not carry the same clips: one may have
  /// `Run` where another has only `Walk`, and the same gesture is spelled two
  /// ways across two files. A game says what it would like in order; this tries
  /// each until the model has one, which only this side can do — the appearance
  /// does not know what is in the file and should not have to.
  ///
  /// Empty leaves whatever is playing alone, which is what a model with no
  /// animation in it wants.
  ///
  /// Named rather than indexed on purpose: an index is a promise about the
  /// order inside somebody else's export.
  List<String> clipsFor(Actor actor);
}

/// Where the monsters are, and which way they are facing.
///
/// Capsules the size of their own collision shapes, which is deliberate rather
/// than lazy: a placeholder that matches the hitbox exactly means every
/// complaint about a shot that should have landed is a complaint about the
/// aiming and not about the art being the wrong size. When rigged models
/// arrive, the mesh changes here and nothing else does.
///
/// One mesh per kind, uploaded once and shared by every node — the only form of
/// instancing flutter_gpu offers. What colour they are is an [ActorAppearance];
/// this owns the shape, the placement and the death pose.
final class ActorVisuals {
  ActorVisuals(
    this.scene, {
    required this.appearance,
    required GraphicsDevice device,
  })  : _meshes = SharedMeshes(device),
        _device = device;

  final Scene scene;

  /// The game's half: one material per monster and per state.
  final ActorAppearance appearance;

  final SharedMeshes _meshes;
  final GraphicsDevice _device;

  /// The white pixel a model's untextured material falls back to. Set by the
  /// caller when it has the renderer's own, so a monster and a wall are not
  /// lit against two different whites.
  TextureHandle? fallbackAlbedo;
  final Map<Actor, SceneNode> _nodes = <Actor, SceneNode>{};

  /// Every model asked for so far, by path. One load per file, however many
  /// actors are drawn with it.
  final Map<String, Future<ModelAsset?>> _models = <String, Future<ModelAsset?>>{};

  /// The animation of each actor that has one.
  final Map<Actor, AnimationPlayer> _players = <Actor, AnimationPlayer>{};

  /// What each one was last told to play, so a cross-fade is started once and
  /// not restarted sixty times a second.
  final Map<Actor, String> _playing = <Actor, String>{};

  /// Gives an actor something to be drawn as.
  ///
  /// An actor with no body is skipped rather than refused: a turret, a trigger
  /// or a director is a perfectly good actor and simply is not a capsule. What
  /// draws those is the game's own business.
  void add(Actor actor) {
    final body = actor.body;
    if (body == null) return;

    final model = appearance.modelFor(actor);
    if (model != null) {
      // The capsule goes in first and is replaced when the file arrives. The
      // alternative — nothing until it loads — is a monster that walks up to
      // you invisible, which is worse than one that is briefly a capsule.
      _addCapsule(actor, body);
      unawaited(_dress(actor, model));
      return;
    }
    _addCapsule(actor, body);
  }

  void _addCapsule(Actor actor, CharacterController body) {
    // Straight off the body, so this works for anything with one. It used to
    // read a `MonsterDef`, which is how the renderer's bridge came to depend on
    // a shooter's idea of what walks about in a level.
    final radius = body.halfExtents.x;
    final height = body.halfExtents.y * 2.0;
    final key = appearance.meshKeyFor(actor);
    final mesh = _meshes.shape(
      'actor:$key',
      () => CapsuleShape(radius: radius, height: height),
    );

    final node = MeshNode(mesh, appearance.materialFor(actor), name: key);
    scene.add(node);
    _nodes[actor] = node;
  }

  /// Swaps an actor's capsule for its model once the file has been read.
  Future<void> _dress(Actor actor, String path) async {
    final asset = await _models.putIfAbsent(path, () => _load(path));
    // Dead by the time it arrived, or the level changed underneath it. Both
    // happen: a runner can be shot before its own model finishes loading.
    if (asset == null || !_nodes.containsKey(actor)) return;

    final instance = asset.instantiate(scene);
    final capsule = _nodes.remove(actor);
    if (capsule != null) scene.remove(capsule);

    _nodes[actor] = instance.root;
    final player = instance.player;
    if (player != null) _players[actor] = player;
  }

  Future<ModelAsset?> _load(String path) async {
    try {
      final document = await decodeModelInIsolate(
        ModelLoadRequest(source: BundleAssetSource(path)),
      );
      return await ModelAsset.fromDocument(
        document,
        device: _device,
        fallbackAlbedo: fallbackAlbedo ?? SolidColorTexture.white.upload(_device),
        name: path,
      );
    } catch (error) {
      // A missing or broken model leaves every actor that wanted it a capsule,
      // which is a level somebody can still play through and report.
      debugPrint('actors: could not load $path, staying a capsule ($error)');
      return null;
    }
  }

  /// Advances every animation. Once a frame, with the frame's own delta.
  void animate(double dt) {
    for (final entry in _players.entries) {
      final wanted = appearance.clipsFor(entry.key);
      // The first the model actually has. `crossFadeToNamed` reports whether
      // the name was there, so a clip this export does not carry is a miss
      // rather than a crash — and the next candidate gets a turn.
      for (final name in wanted) {
        if (_playing[entry.key] == name) break;
        // Only on a change: `crossFadeToNamed` restarts the fade every time it
        // is called, so calling it per frame is an animation that never gets
        // anywhere — always a tenth of a second into the same blend.
        if (entry.value.crossFadeToNamed(name)) {
          _playing[entry.key] = name;
          break;
        }
      }
      entry.value
        ..update(dt)
        ..apply();
    }
  }

  /// Moves every node to its actor.
  ///
  /// Called once per frame rather than per simulation step: this is display,
  /// and the simulation does not care where the capsules are.
  void sync() {
    for (final entry in _nodes.entries) {
      final actor = entry.key;
      final node = entry.value;
      final position = actor.position!;

      // Only a capsule takes the game's material; a model brings its own, and
      // painting over it would make three monsters one colour.
      if (node is MeshNode) node.material = appearance.materialFor(actor);

      if (!actor.isAlive && !_players.containsKey(actor)) {
        // Laid on its side and sunk, which reads as a corpse without needing a
        // death animation. It stays: an emptied corridor should show what
        // happened in it.
        node
          ..setPosition(
            position.x,
            position.y - actor.body!.halfExtents.y * 0.64,
            position.z,
          )
          ..setRotation(
            Quaternion.axisAngle(Vector3(1.0, 0.0, 0.0), math.pi / 2.0),
          );
        continue;
      }

      node
        ..setPositionFrom(position)
        ..setRotation(Quaternion.axisAngle(Vector3(0.0, 1.0, 0.0), actor.yaw));
    }
  }
}
