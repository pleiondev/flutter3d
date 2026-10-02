import 'package:flutter3d_core/formats.dart';

import '../animation_layer.dart';
import '../pose.dart';
import 'animation_parameters.dart';
import 'animation_state_machine.dart';

/// Runs an [AnimationStateMachine] over a set of clips, one fixed step at a
/// time, into a [Pose] — N1's core.
///
/// **Advanced by the step, not by the frame.** [evaluate] is handed the
/// simulation's own `stepSeconds`, the way everything else a run steps is, so
/// the same parameters written on the same steps take the same transitions on
/// every machine and on every replay. Which state the graph is in, how far
/// into it and how far through a fade are sums and quotients of step lengths
/// and nothing else; the pose it hands back passes through the same slerp a
/// clip's own keys do, which is the frame's arithmetic and not part of what a
/// run has to agree on.
///
/// **One transition a step, and none during a crossfade.** A fade that could
/// be interrupted would need the half-blended pose frozen as the new source,
/// which is a second kind of state for a snapshot to carry; until a graph
/// needs that, a trigger set during a fade waits for it to finish, which is
/// what [AnimationParameterType.trigger]'s buffering is for.
///
/// **The crossfade is the player's.** The outgoing state keeps playing while
/// the incoming one comes in, and the two are mixed by [Pose.blendFrom], which
/// is `AnimationPlayer`'s own blend on whole poses. Whole poses is the one
/// difference: a joint the outgoing clip does not animate is faded from its
/// rest, where the player, which fades track by track, has nothing to fade
/// it from and cuts.
final class AnimationGraph {
  /// Builds a graph over [machine], playing [clips] into [pose].
  ///
  /// Throws an [ArgumentError] listing [AnimationStateMachine.problems] when
  /// there are any: a definition that cannot run is a bug in whoever built
  /// it, and a tool that wants to refuse politely asks `problems` first.
  factory AnimationGraph({
    required AnimationStateMachine machine,
    required List<AnimationClip> clips,
    required Pose pose,
  }) {
    final problems = machine.problems(clips);
    if (problems.isNotEmpty) {
      throw ArgumentError(
        'This animation graph cannot run:\n- ${problems.join('\n- ')}',
      );
    }
    final byName = <String, AnimationClip>{
      for (final clip in clips.reversed) ?clip.name: clip,
    };
    final outgoing = <List<_Transition>>[
      for (final state in machine.states) _outgoingFrom(machine, state.name),
    ];
    return AnimationGraph._(
      machine,
      AnimationParameters(machine.parameters),
      <AnimationClip>[for (final state in machine.states) byName[state.clip]!],
      outgoing,
      pose,
    );
  }

  AnimationGraph._(
    this.machine,
    this.parameters,
    this._clips,
    this._outgoing,
    this.pose,
  ) : _from = pose.restCopy(),
      _current = machine.indexOfState(machine.entry) {
    _sample();
  }

  final AnimationStateMachine machine;

  /// The values the transitions test; written by the game between steps.
  final AnimationParameters parameters;

  /// What [evaluate] writes into and returns.
  final Pose pose;

  /// The clip each state plays, index-aligned with the machine's states.
  final List<AnimationClip> _clips;

  /// Each state's way out, highest priority first.
  final List<List<_Transition>> _outgoing;

  /// Where the outgoing state is sampled during a crossfade.
  final Pose _from;

  int _current;
  _Playhead _head = _Playhead.start;

  /// The state being faded out of, or -1 when there is no crossfade.
  int _previous = -1;
  _Playhead _previousHead = _Playhead.start;
  double _fadeElapsed = 0.0;
  double _fadeDuration = 0.0;

  /// The state the graph is in — during a crossfade, the one it is entering.
  String get state => machine.states[_current].name;

  /// The state being faded out of, or null.
  String? get fadingFrom =>
      _previous < 0 ? null : machine.states[_previous].name;

  /// How much of [state] the pose holds: 1 unless a crossfade is under way.
  double get fadeWeight => _previous < 0 ? 1.0 : _fadeElapsed / _fadeDuration;

  /// The playhead in [state]'s clip, in seconds.
  double get stateTime => _head.time;

  /// How far into [state] the graph is, in lengths of its clip — what an exit
  /// time is compared against.
  double get normalizedTime => _normalized(_current, _head);

  /// Advances by [dt] seconds, takes at most one transition, and returns
  /// [pose] holding the result.
  ///
  /// A [dt] that is not a finite positive number advances nothing, the way
  /// `FixedStep.advance` treats a clock that went backwards; transitions are
  /// still tested, so a parameter written between steps is seen on the next
  /// one whatever the clock did.
  Pose evaluate(double dt) {
    final step = dt.isFinite && dt > 0.0 ? dt : 0.0;
    _head = _advance(_current, _head, step);
    if (_previous >= 0) {
      _previousHead = _advance(_previous, _previousHead, step);
      _fadeElapsed += step;
      if (_fadeElapsed >= _fadeDuration) _previous = -1;
    }
    if (_previous < 0) _takeTransition();
    _sample();
    return pose;
  }

  void _takeTransition() {
    final normalized = _normalized(_current, _head);
    for (final transition in _outgoing[_current]) {
      if (transition.exitTime case final exit? when normalized < exit) {
        continue;
      }
      if (!transition.checks.every(_holds)) continue;
      for (final check in transition.checks) {
        if (check.condition is TriggerCondition) {
          parameters.consumeTriggerAt(check.parameter);
        }
      }
      if (transition.duration > 0.0) {
        _previous = _current;
        _previousHead = _head;
        _fadeElapsed = 0.0;
        _fadeDuration = transition.duration;
      }
      _current = transition.to;
      _head = _Playhead.start;
      return;
    }
  }

  bool _holds(_Check check) {
    final actual = parameters.valueAt(check.parameter);
    return switch (check.condition) {
      final CompareCondition c => c.holds(actual),
      BoolCondition(:final value) => (actual != 0.0) == value,
      TriggerCondition() => actual != 0.0,
    };
  }

  _Playhead _advance(int state, _Playhead head, double step) {
    final length = _clips[state].duration;
    final delta = step * machine.states[state].speed;
    if (length <= 0.0 || delta == 0.0) {
      return _Playhead(head.time, head.elapsed + delta, head.reversing);
    }
    final moved = advanceTime(
      time: head.time,
      deltaSeconds: delta,
      length: length,
      wrap: machine.states[state].wrap,
      reversing: head.reversing,
    );
    return _Playhead(moved.time, head.elapsed + delta, moved.reversing);
  }

  /// A clip with no length is a single pose, done as soon as it is entered.
  double _normalized(int state, _Playhead head) {
    final length = _clips[state].duration;
    return length <= 0.0 ? 1.0 : head.elapsed / length;
  }

  void _sample() {
    pose.sampleClip(_clips[_current], _head.time);
    if (_previous < 0) return;
    _from.sampleClip(_clips[_previous], _previousHead.time);
    pose.blendFrom(_from, fadeWeight);
  }

  static List<_Transition> _outgoingFrom(
    AnimationStateMachine machine,
    String from,
  ) {
    final declared = <(int, AnimationTransition)>[
      for (final (i, t) in machine.transitions.indexed)
        if (t.from == from) (i, t),
    ];
    // `List.sort` is not stable, so declaration order is made part of the key
    // rather than hoped for.
    declared.sort(
      (a, b) => switch (b.$2.priority.compareTo(a.$2.priority)) {
        0 => a.$1.compareTo(b.$1),
        final order => order,
      },
    );
    return <_Transition>[
      for (final (_, t) in declared)
        _Transition(
          to: machine.indexOfState(t.to),
          duration: t.duration,
          exitTime: t.exitTime,
          checks: <_Check>[
            for (final c in t.conditions)
              _Check(machine.parameters.indexOf(c.parameter), c),
          ],
        ),
    ];
  }
}

/// Where a state's clip is, and how long the graph has been in the state.
///
/// [elapsed] is not wrapped: an exit time counts from entering the state, so
/// a loop that has gone round must not read as having just begun.
final class _Playhead {
  const _Playhead(this.time, this.elapsed, this.reversing);

  static const _Playhead start = _Playhead(0.0, 0.0, false);

  final double time;
  final double elapsed;
  final bool reversing;
}

/// A transition with its names resolved to indices.
final class _Transition {
  const _Transition({
    required this.to,
    required this.duration,
    required this.exitTime,
    required this.checks,
  });

  final int to;
  final double duration;
  final double? exitTime;
  final List<_Check> checks;
}

final class _Check {
  const _Check(this.parameter, this.condition);

  final int parameter;
  final AnimationCondition condition;
}
