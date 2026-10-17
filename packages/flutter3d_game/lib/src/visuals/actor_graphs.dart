import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';

/// A modelled actor animated by a graph rather than by naming clips — N1.
///
/// `ActorVisuals` plays an actor's clips by asking its appearance which to
/// play now and cross-fading to it. A game that hands it one of these instead
/// gets an [AnimationGraph] per actor, built over the model's own clips from
/// the [AnimationStateMachine] [machineFor] gives. [dress] adds what the
/// game lays on it — layers, goals — once it is built; [drive] writes what
/// the actor is doing into its parameters, and moves its goals' targets,
/// once a frame; the graph's states, transitions, fades and exit times
/// decide what is drawn. The appearance's
/// clip names go on serving the actors whose model this gives no machine for.
///
/// Display, as the clips were: evaluated on the frame with the frame's delta.
/// A graph whose state a run must agree on — one that moves a body by its
/// root motion — belongs to the simulation's step instead.
///
/// **Mixed in, not implemented**, outside this library: a `base` type, so a
/// member added in a 1.x release arrives with a body and nothing that mixes
/// it in has to change.
abstract base mixin class ActorGraphs {
  /// The machine for the context's actor drawn with its clips; null to name
  /// its clips as before.
  AnimationStateMachine? machineFor(ActorMachineContext context);

  /// The context's graph, just built for its actor drawn as its model:
  /// anything the game lays on it — a look, a reach, a layer — added here,
  /// once.
  void dress(ActorDressContext context);

  /// What the context's actor is doing, into its graph's parameters, and
  /// where its goals aim: once a frame, before it is evaluated. The model is
  /// where it is drawn: a goal's target is in the space of its root,
  /// `inverse(model.root.worldMatrix)` times a point in the world.
  void drive(ActorDriveContext context);
}

/// What [ActorGraphs.machineFor] is handed: the actor and the clips its
/// model has.
///
/// **One object, so a minor can hand a game's graphs more** without
/// breaking ones written against 1.0.
final class ActorMachineContext {
  const ActorMachineContext({required this.actor, required this.clips});

  /// The actor whose model was just placed.
  final Actor actor;

  /// The clips the model carries.
  final List<AnimationClip> clips;
}

/// What [ActorGraphs.dress] is handed, once per graph, for the reason
/// [ActorMachineContext] gives.
final class ActorDressContext {
  const ActorDressContext({
    required this.actor,
    required this.graph,
    required this.model,
  });

  /// The actor the graph animates.
  final Actor actor;

  /// The graph, just built over the model's clips.
  final AnimationGraph graph;

  /// Where the actor is drawn.
  final ModelInstance model;
}

/// What [ActorGraphs.drive] is handed, once a frame per actor, for the
/// reason [ActorMachineContext] gives.
///
/// **Reused**: `ActorVisuals` owns one and sets it for each actor each
/// frame, so driving allocates nothing; a game reads it during the call and
/// does not keep it.
final class ActorDriveContext {
  ActorDriveContext({
    required this.actor,
    required this.graph,
    required this.model,
  });

  /// The actor the graph animates.
  Actor actor;

  /// Its graph, evaluated after this call.
  AnimationGraph graph;

  /// Where the actor is drawn.
  ModelInstance model;
}
