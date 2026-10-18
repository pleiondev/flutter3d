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
  /// The context's actor has died, drawn as its model. True when this takes
  /// its pose over; false leaves it to its death clip.
  bool begin(ActorDeathContext context);

  /// Once a frame, after the living have been animated, with the frame's dt.
  void step(double dt);

  /// [actor] has been taken out of the scene, or stands again — a rewind or
  /// a rollback to before its death — and is animated as the living are.
  /// May come for an actor this has already let go, and then does nothing.
  void end(Actor actor);

  /// The level is over: everything [begin] made goes.
  void dispose();
}

/// What [ActorCorpses.begin] is handed, once per death: the actor, its
/// model, and the motion it died in.
///
/// **One object, so a minor can hand the corpses more** — the blow that
/// killed it, the step it died at — without breaking ones written against
/// 1.0.
final class ActorDeathContext {
  /// The death of [actor], drawn by [model]; [dt] is a sixtieth of a
  /// second unless given.
  const ActorDeathContext({
    required this.actor,
    required this.model,
    this.previous,
    this.dt = 1.0 / 60.0,
  });

  /// The actor that died.
  final Actor actor;

  /// Where it is drawn.
  final ModelInstance model;

  /// Every joint's world matrix of its first skeleton a frame before, [dt]
  /// seconds before, when they were kept; null when they were not.
  final List<Matrix4>? previous;

  /// The seconds between [previous] and now.
  final double dt;
}
