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
///
/// **Made on an actor's first step, by [graphFor].** A level whose monsters
/// spawn as it goes has no moment to attach theirs, and a graph made inside
/// the step is made at the same step of every run, so a replay agrees with
/// the run it records. [attach] is for a game that makes its own.
final class ActorAnimations implements ActorStrides {
  /// [write] is asked every step for each actor with a graph, before it
  /// moves; null leaves the parameters to whoever set them.
  ActorAnimations({this.events, this.write, this.graphFor, this.scaleOf});

  /// Where markers are reported; the game's own buffer, as the actor
  /// system's is.
  GameEvents? events;

  /// Puts what [actor]'s brain decided — and where it wished to go this
  /// step — into its graph's parameters, and where its goals look and stand.
  final void Function(Actor actor, AnimationGraph graph, Vector3 wish)? write;

  /// The graph [actor] is animated by, asked once on its first step; null
  /// for one that is not.
  final AnimationGraph? Function(Actor actor)? graphFor;

  /// How large [graphFor]'s actor's model is drawn — its stride walks that
  /// much further — or null for its own size.
  final double Function(Actor actor)? scaleOf;

  final Map<Actor, _Animated> _animated = <Actor, _Animated>{};

  /// The actors [graphFor] has answered for, with a graph or without.
  final Set<Actor> _asked = <Actor>{};

  /// Steps [graph] for [actor] from now on. [scale] is the model's size: a
  /// stride authored for a model drawn at half size walks half as far.
  void attach(Actor actor, AnimationGraph graph, {double scale = 1.0}) =>
      _animated[actor] = _Animated(graph, scale);

  /// Stops stepping [actor]'s graph — for an actor removed from the world.
  void detach(Actor actor) {
    _animated.remove(actor);
    _asked.remove(actor);
  }

  /// The graph stepped for [actor], posed as the last step left it.
  AnimationGraph? graphOf(Actor actor) => _animated[actor]?.graph;

  @override
  Vector3? strideOf(Actor actor, Vector3 wish, double dt) {
    final animated = _animated[actor] ?? _made(actor);
    if (animated == null) return null;
    final graph = animated.graph;
    write?.call(actor, graph, wish);
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

  _Animated? _made(Actor actor) {
    final graphFor = this.graphFor;
    if (graphFor == null || !_asked.add(actor)) return null;
    final graph = graphFor(actor);
    if (graph == null) return null;
    return _animated[actor] = _Animated(
      graph,
      scaleOf?.call(actor) ?? 1.0,
      made: true,
    );
  }

  /// Every graph's state, by the ordinal of the actor it animates — the
  /// same actors are at the same ordinals when a level is loaded again.
  @override
  Map<String, Object?> save() => <String, Object?>{
    for (final MapEntry(key: actor, value: animated) in _animated.entries)
      '${actor.ordinal}': animated.graph.save(),
  };

  /// Back to what [save] wrote, for [actors] as they now are.
  ///
  /// An actor saved with a graph gets it back, made by [graphFor] if this
  /// run has not made it yet; one saved without had not taken its first
  /// step, and its graph is made again when it does — as it was in the run
  /// that saved. An attached graph with nothing saved is left as it stands.
  @override
  void restore(Object? from, Iterable<Actor> actors) {
    final saved = from is Map ? from : const <String, Object?>{};
    final present = actors.toSet();
    _animated.removeWhere((actor, animated) => !present.contains(actor));
    _asked.removeWhere((actor) => !_animated.containsKey(actor));
    for (final actor in present) {
      final state = saved['${actor.ordinal}'];
      final animated = _animated[actor];
      if (state is Map<String, Object?>) {
        (animated ?? _made(actor))?.graph.restore(state);
      } else if (animated != null && animated.made) {
        _animated.remove(actor);
        _asked.remove(actor);
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
  _Animated(this.graph, this.scale, {this.made = false});

  final AnimationGraph graph;
  final double scale;

  /// Made by [ActorAnimations.graphFor] rather than attached.
  final bool made;

  /// The model's turn and size, written afresh each step.
  final Matrix4 facing = Matrix4.identity();
}
