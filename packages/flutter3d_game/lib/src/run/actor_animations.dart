import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart' hide Pose;
import 'package:vector_math/vector_math.dart';

import '../visuals/actor_visuals.dart';

/// Actors' animation graphs stepped by the simulation — N1: where an
/// animation is part of the game rather than a picture of it.
///
/// Set as `ActorSystem.strides`, this steps each attached actor's graph on
/// the game's fixed step, after its brain has acted: [write] puts what the
/// brain decided into the graph's parameters, the graph moves, and
///
/// - its root motion, if it has a root node, walks the body — carried into
///   the world by the way the actor faces and [scale], and swept by the
///   body's controller, so a stride into a wall stops there;
/// - each marker the entered state passed goes into [events] as an
///   [AnimationMarkerPassed], in order with the shots and deaths of the same
///   step, so a footstep can wake a monster and a swing can land on the
///   frame it was drawn to.
///
/// Because it is the simulation's, it is in a save: [save] and [restore]
/// carry every graph across, so a rewind or a replay steps on to the same
/// poses, strides and markers.
///
/// **Drawing is still `ActorVisuals`' business**: it may draw [graphOf] an
/// actor as it stands, rather than stepping a graph of its own on the frame.
final class ActorAnimations implements ActorStrides {
  /// [write] is asked every step for each attached actor; null leaves the
  /// parameters to whoever set them.
  ActorAnimations({this.events, this.write});

  /// Where markers are reported; the game's own buffer, as the actor
  /// system's is.
  GameEvents? events;

  /// Puts what [actor]'s brain decided into its graph's [parameters].
  final void Function(Actor actor, AnimationParameters parameters)? write;

  final Map<Actor, _Animated> _animated = <Actor, _Animated>{};

  /// Steps [graph] for [actor] from now on. [scale] is the model's size: a
  /// stride authored for a model drawn at half size walks half as far.
  void attach(Actor actor, AnimationGraph graph, {double scale = 1.0}) =>
      _animated[actor] = _Animated(graph, scale);

  /// Stops stepping [actor]'s graph — for an actor removed from the world.
  void detach(Actor actor) => _animated.remove(actor);

  /// The graph stepped for [actor], posed as the last step left it.
  AnimationGraph? graphOf(Actor actor) => _animated[actor]?.graph;

  @override
  Vector3? strideOf(Actor actor, double dt) {
    final animated = _animated[actor];
    if (animated == null) return null;
    final graph = animated.graph;
    write?.call(actor, graph.parameters);
    graph.evaluate(dt);
    for (final passed in graph.passed) {
      events?.add(AnimationMarkerPassed(actor, passed.state, passed.name));
    }
    if (graph.rootNode == null) return null;
    return graph.rootDeltaIn(
      animated.facing..setFromTranslationRotationScale(
        Vector3.zero(),
        Quaternion.axisAngle(
          Vector3(0.0, 1.0, 0.0),
          ActorVisuals.yawFor(actor, model: true),
        ),
        Vector3.all(animated.scale),
      ),
    );
  }

  /// Every graph's state, by the ordinal of the actor it animates — the
  /// same actors are at the same ordinals when a level is loaded again.
  Map<String, Object?> save() => <String, Object?>{
    for (final MapEntry(key: actor, value: animated) in _animated.entries)
      '${actor.ordinal}': animated.graph.save(),
  };

  /// Back to what [save] wrote; an actor with nothing saved is left as it
  /// stands.
  void restore(Object? from) {
    if (from is! Map) return;
    for (final MapEntry(key: actor, value: animated) in _animated.entries) {
      if (from['${actor.ordinal}'] case final Map<String, Object?> saved) {
        animated.graph.restore(saved);
      }
    }
  }
}

/// [actor]'s animation passed marker [name] in [state] this step.
final class AnimationMarkerPassed extends GameEvent {
  const AnimationMarkerPassed(this.actor, this.state, this.marker);

  final Actor actor;

  /// The state whose clip carries the marker.
  final String state;

  /// What the marker is called — `step`, `swing`.
  final String marker;

  @override
  String get name => 'animation marker $marker in $state';
}

final class _Animated {
  _Animated(this.graph, this.scale);

  final AnimationGraph graph;
  final double scale;

  /// The model's turn and size, written afresh each step.
  final Matrix4 facing = Matrix4.identity();
}
