import 'dart:async';
import 'dart:math' as math;

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:vector_math/vector_math.dart';

import 'actor_appearance.dart';
import 'shared_meshes.dart';

export 'actor_appearance.dart';

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
    IssueSink? onIssue,
  })  : _meshes = SharedMeshes(device),
        _device = device,
        onIssue = onIssue ?? printIssue;

  final Scene scene;

  /// Where this says what it could not draw.
  ///
  /// A model that will not load leaves every actor that wanted it a capsule.
  /// That is playable, which is why it is not an exception — and invisible,
  /// which is why it must not be silent: a capsule is also what an actor with
  /// no model at all looks like.
  final IssueSink onIssue;

  /// The game's half: one material per monster and per state.
  final ActorAppearance appearance;

  final SharedMeshes _meshes;
  final GraphicsDevice _device;

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
        name: path,
      );
    } catch (error) {
      // A missing or broken model leaves every actor that wanted it a capsule,
      // which is a level somebody can still play through and report.
      onIssue('actors: could not load $path, staying a capsule ($error)');
      return null;
    }
  }

  /// Which way to turn what is drawn for [actor], in radians.
  ///
  /// **A model faces the other way to a capsule.** An actor's yaw is the
  /// direction it is walking — the shooter builds its forward as
  /// `(-sin(yaw), 0, -cos(yaw))`, so yaw nought points down -Z — and a
  /// character exported from Blender through glTF faces +Z. That is half a
  /// turn apart, so every monster walked at the player backwards and fell over
  /// backwards, which is what it looked like from the corridor.
  ///
  /// A capsule never showed it, being round about the axis it spins on, so this
  /// arrived with the models and not with the code that placed them.
  ///
  /// [model] is false for the capsule an actor is drawn as before its model
  /// loads, and for one whose model never does.
  static double yawFor(Actor actor, {required bool model}) =>
      model ? actor.yaw + math.pi : actor.yaw;

  /// How [actor]'s clip should behave when it runs off its end.
  ///
  /// **A corpse does not die twice.** [AnimationPlayer.wrap] defaults to
  /// looping and nothing set it, so a monster's death clip started over the
  /// moment it finished: the frog fell, snapped upright and fell again, for
  /// ever, in a room the player had already cleared.
  /// [AnimationWrap.once] holds the final pose, which is the pose a body
  /// should be left in.
  ///
  /// Read from the actor rather than from the clip's name, because the name
  /// belongs to whoever exported the model: two of the crypt's three files
  /// spell their hit clip differently, and the death clip in the fourth model
  /// somebody adds will be called whatever that artist called it. Being dead is
  /// not a spelling.
  ///
  /// Its own method because that is the whole of what can be tested without a
  /// device: reaching the line inside [animate] means uploading a rigged model
  /// to a GPU to look at one enum.
  static AnimationWrap wrapFor(Actor actor) =>
      actor.isAlive ? AnimationWrap.loop : AnimationWrap.once;

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
        ..wrap = wrapFor(entry.key)
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

      // A capsule is a shape about its middle and sits on the body's centre;
      // a model of somebody standing has its feet at its origin. The same two
      // conventions the platformer reconciles every frame for its runner —
      // rooted at the centre, a monster's model hovers half its height off
      // the floor from the moment it replaces its capsule.
      final isModel = node is! MeshNode;
      final drop = isModel ? actor.body!.halfExtents.y : 0.0;
      node
        ..setPosition(position.x, position.y - drop, position.z)
        ..setRotation(Quaternion.axisAngle(
          Vector3(0.0, 1.0, 0.0),
          yawFor(actor, model: isModel),
        ));
    }
  }
}
