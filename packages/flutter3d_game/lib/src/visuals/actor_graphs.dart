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
  /// The machine for [actor] drawn with [clips]; null to name its clips as
  /// before.
  AnimationStateMachine? machineFor(Actor actor, List<AnimationClip> clips);

  /// [graph], just built for [actor] drawn as [model]: anything the game
  /// lays on it — a look, a reach, a layer — added here, once.
  void dress(Actor actor, AnimationGraph graph, ModelInstance model);

  /// What [actor] is doing, into [graph]'s parameters, and where its goals
  /// aim: once a frame, before it is evaluated. [model] is where it is
  /// drawn: a goal's target is in the space of its root,
  /// `inverse(model.root.worldMatrix)` times a point in the world.
  void drive(Actor actor, AnimationGraph graph, ModelInstance model);
}
