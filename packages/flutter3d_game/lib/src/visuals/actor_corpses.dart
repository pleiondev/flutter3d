import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:vector_math/vector_math.dart';

/// What becomes of a modelled actor when it dies, in place of its death clip
/// — N1.
///
/// `ActorVisuals` plays a death clip by default and holds its last frame. A
/// game that would rather its monsters fell as bodies hands it one of these:
/// the moment a modelled actor is seen dead, [begin] is asked whether to take
/// the actor's pose over, and from then on its animation is not updated and
/// its model not moved — what the joints hold is this one's to write, once a
/// frame in [step]. A ragdoll is the reason, and lives where the physics core
/// does, so this package names neither.
///
/// **Mixed in, not implemented**, outside this library: a `base` type, so a
/// member added in a 1.x release arrives with a body and nothing that mixes
/// it in has to change.
abstract base mixin class ActorCorpses {
  /// [actor] has died, drawn as [model]. True when this takes its pose over;
  /// false leaves it to its death clip. [previous] is every joint's world
  /// matrix of its first skeleton a frame before, [dt] seconds before, when
  /// they were kept — the motion it died in.
  bool begin(
    Actor actor,
    ModelInstance model, {
    List<Matrix4>? previous,
    double dt,
  });

  /// Once a frame, after the living have been animated, with the frame's dt.
  void step(double dt);

  /// [actor] has been taken out of the scene.
  void end(Actor actor);

  /// The level is over: everything [begin] made goes.
  void dispose();
}
