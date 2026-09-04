import 'dart:math' as math;

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_bridge/flutter3d_bridge.dart';
import 'package:flutter3d_game_platformer/flutter3d_game_platformer.dart';
import 'package:vector_math/vector_math.dart';

import 'runner_clips.dart';

/// What the player sees themselves as, and everything that decides it.
///
/// **Six fields and three methods that only ever spoke to each other.** They sat
/// in `_GameScreenState` beside the audio, the settings and the pad, and nothing
/// but the posing code outside this file ever read one of them. Gathered here
/// the widget keeps one object instead of six, and the two conventions this has
/// to reconcile — where a model's feet are and which way it was exported facing
/// — are stated once, next to the code that applies them.
final class RunnerVisuals {
  RunnerVisuals({required this.model, this.modelFacing = 0.0});

  /// The asset to dress the runner in, once it has been read.
  final String model;

  /// Added to the runner's yaw, for a model exported facing the other way.
  ///
  /// A number rather than a re-authored mesh. Zero until the model arrives, so
  /// the box is not turned by a correction meant for something else.
  final double modelFacing;

  /// A model when one loads, a box when it does not.
  ///
  /// The game is playable either way, and a missing asset should not be the
  /// difference between playing and staring at an error.
  SceneNode? node;

  /// The model's own lowest point, in its local space.
  ///
  /// A body is a box about its middle; a model of somebody standing has its feet
  /// at or near the origin. Reconciled every frame rather than once at load,
  /// because a crouch moves the body's middle and a fixed offset does not follow
  /// it.
  double modelFloor = 0.0;

  /// [modelFacing], but only once there is a model to apply it to.
  double facing = 0.0;

  /// The loaded model, held so that nothing collects it out from under the
  /// scene. `FixtureVisuals` keeps its assets in a cache for the same reason.
  ModelAsset? asset;

  /// The clips on the runner's model, when it has any.
  AnimationPlayer? animation;

  /// What is playing now, so a crossfade is asked for once rather than sixty
  /// times a second.
  String? _clip;

  /// A box, right away, so the game can be played while the model loads.
  SceneNode box(GraphicsDevice device, Scene scene, Runner runner) {
    final box = MeshNode(
      SharedMeshes(device).box(runner.body.halfExtents * 2.0),
      Material(
        name: 'runner',
        baseColor: Vector4(0.90, 0.42, 0.28, 1.0),
        lighting: LightingModel.pbr,
      )..roughness = 0.5,
      name: 'runner box',
    );
    scene.add(box);
    node = box;
    return box;
  }

  /// Swaps the box for the model once it has been read and uploaded.
  ///
  /// **Not awaited before the first frame, and that is the whole point.** The
  /// model in the scene before the renderer has ever built its frame targets is
  /// the arrangement that fails here: `_ensureTargets` cannot allocate, every
  /// frame, from the first, and the picture is an error screen. The same file
  /// through `FixtureVisuals` is fine, and the difference is that a modelled
  /// fixture arrives *after* the frames have started — so this does too.
  ///
  /// The asset is authored at the size the game wants (`tool/prepare_models.py`
  /// bakes the scale into its root), so no scale is set at load either — what
  /// `setScale` carries is the pose, and nothing else.
  ///
  /// [stillWanted] is asked immediately before anything is swapped, and it is
  /// not a formality — see the note in `dressRunner` at the call site.
  Future<void> dress(
    GraphicsDevice device,
    Scene scene,
    Runner runner, {
    required bool Function() stillWanted,
    required void Function() onArrived,
  }) async {
    try {
      final document = await decodeModelInIsolate(
        ModelLoadRequest(source: BundleAssetSource(model)),
      );
      final loaded = await ModelAsset.fromDocument(
        document,
        device: device,
        name: model,
      );
      if (!stillWanted()) return;

      final instance = loaded.instantiate(scene, name: 'runner');
      final previous = node;
      asset = loaded;
      node = instance.root;
      // **The line three stages of this game were waiting for.** The player is
      // built by `instantiate` when the model has clips, and thrown away when
      // it has none — which is what happened silently for as long as the
      // player was not kept. The shipped penguin still has no clips, so this is
      // null for it; `RunnerClips` names the eight a rigged runner would drive,
      // and `runner_looks_test.dart` asserts them against `hero.glb` in the
      // engine's fixtures, because asserting them against the penguin would
      // assert nothing.
      animation = instance.player;
      modelFloor = loaded.localBounds.min.y;
      facing = modelFacing;
      onArrived();
      if (previous != null) scene.remove(previous);
    } catch (error) {
      debugPrint('runner: could not load $model, staying a box ($error)');
    }
  }

  /// Advances whatever the runner is doing, and starts a fade when it changes.
  void animate(double dt, Runner? runner) {
    final player = animation;
    if (player == null || runner == null) return;

    final wanted = RunnerClips.forRunner(runner);
    if (wanted != _clip) {
      // A short fade, and shorter still into a jump: a quarter of a second of
      // blending into a take-off is a quarter of a second of the runner still
      // standing there while the body is already in the air.
      player.crossFadeToNamed(
        wanted,
        duration: wanted == RunnerClips.jump ? 0.06 : 0.14,
      );
      _clip = wanted;
    }

    final velocity = runner.body.velocity;
    final speed = math.sqrt(velocity.x * velocity.x + velocity.z * velocity.z);
    player
      ..speed = RunnerClips.rateFor(wanted, speed)
      ..update(dt);
  }
}
