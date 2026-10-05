import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';

/// A modelled actor animated by a graph rather than by naming clips — N1.
///
/// `ActorVisuals` plays an actor's clips by asking its appearance which to
/// play now and cross-fading to it. A game that hands it one of these instead
/// gets an [AnimationGraph] per actor, built over the model's own clips from
/// the [AnimationStateMachine] [machineFor] gives: [drive] writes what the
/// actor is doing into its parameters once a frame, and the graph's states,
/// transitions, fades and exit times decide what is drawn. The appearance's
/// clip names go on serving the actors whose model this gives no machine for.
///
/// Display, as the clips were: evaluated on the frame with the frame's delta.
/// A graph whose state a run must agree on — one that moves a body by its
/// root motion — belongs to the simulation's step instead.
abstract interface class ActorGraphs {
  /// The machine for [actor] drawn with [clips]; null to name its clips as
  /// before.
  AnimationStateMachine? machineFor(Actor actor, List<AnimationClip> clips);

  /// What [actor] is doing, into [parameters]: once a frame, before its
  /// graph is evaluated.
  void drive(Actor actor, AnimationParameters parameters);
}
