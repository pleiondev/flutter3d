import 'dart:typed_data';

import 'package:flutter3d_core/formats.dart';
import 'package:vector_math/vector_math.dart';

import '../animation_layer.dart';
import '../animation_target.dart';
import '../pose.dart';
import 'animation_goals.dart';
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
      <_Plays>[
        for (final state in machine.states)
          if (state.blend case final blend?)
            _Plays.blend(
              machine.parameters.indexOf(blend.parameter),
              <double>[for (final p in blend.points) p.at],
              <AnimationClip>[for (final p in blend.points) byName[p.clip]!],
              parameterY: blend.across == null
                  ? -1
                  : machine.parameters.indexOf(blend.across!),
              ys: <double>[for (final p in blend.points) p.y],
            )
          else
            _Plays.one(byName[state.clip]!),
      ],
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
      _scratch = pose.restCopy(),
      _rest = pose.restCopy(),
      _marks = <List<(double, String)>>[
        for (final (i, state) in machine.states.indexed)
          <(double, String)>[
            for (final m in state.markers) (m.at, m.name),
            if (!_clips[i].blend && _clips[i].clips.first.duration > 0.0)
              for (final m in _clips[i].clips.first.markers)
                (m.at / _clips[i].clips.first.duration, m.name),
          ]..sort((a, b) => a.$1.compareTo(b.$1)),
      ],
      _current = machine.indexOfState(machine.entry) {
    _sample();
  }

  final AnimationStateMachine machine;

  /// The values the transitions test; written by the game between steps.
  final AnimationParameters parameters;

  /// What [evaluate] writes into and returns.
  final Pose pose;

  /// The markers the last [evaluate] passed in the state the graph is in:
  /// each with its state's name, in the order they came. A footstep, a blow
  /// landing — what a game turns into a sound or an event.
  ///
  /// **The entered state's alone.** One fading out passes its markers too,
  /// but a step from the walk a run is replacing is the run's business now,
  /// and two feet down at once is the sound of a seam.
  List<({String state, String name})> get passed =>
      List<({String state, String name})>.unmodifiable(_passed);
  final List<({String state, String name})> _passed =
      <({String state, String name})>[];

  /// The node whose travel along the floor is taken out of the pose and
  /// handed over as [rootDelta] — root motion — or null for none.
  ///
  /// **Along the floor, x and z of the pose's space.** The root keeps its
  /// height from the clip — a hop is the clip's to draw — and its x and z
  /// are held at rest, so the model stays over the body that carries it and
  /// the body is moved by [rootDelta] instead: by a controller that sweeps,
  /// so a walk cycle stops at a wall rather than walking through it.
  int? rootNode;

  /// How far [rootNode] travelled along the floor in the last [evaluate], in
  /// the pose's space: the clip's own travel between the playhead before
  /// and after, across the loop's turn, mixed as the states were mixed —
  /// by a blend's weights, and through a crossfade by the fade's.
  final Vector3 rootDelta = Vector3.zero();

  /// [rootDelta] in the world, for a model whose pose space [poseToWorld]
  /// carries there — the model root's world matrix — turned and scaled by
  /// it and laid flat: what a character controller is handed to move by.
  Vector3 rootDeltaIn(Matrix4 poseToWorld) {
    final out = poseToWorld.rotate3(rootDelta.clone());
    return out..y = 0.0;
  }

  /// Where joints are made to reach or look after the states and layers
  /// have posed them, in order: see [AnimationGoal]. Added by the game.
  final List<AnimationGoal> goals = <AnimationGoal>[];

  /// Graphs laid over this one's pose, each over part of the skeleton, in
  /// order: see [AnimationGraphLayer]. Added and taken away by the game.
  final List<AnimationGraphLayer> layers = <AnimationGraphLayer>[];

  /// What each state plays, index-aligned with the machine's states.
  final List<_Plays> _clips;

  /// Each state's way out, highest priority first.
  final List<List<_Transition>> _outgoing;

  /// Where the outgoing state is sampled during a crossfade.
  final Pose _from;

  /// Where a blend's second clip is sampled before it is mixed in.
  final Pose _scratch;

  /// The pose at rest, never written: where a root's x and z are held.
  final Pose _rest;

  /// Each state's markers, as shares of its cycle, earliest first: its own
  /// and, for a state that plays one clip, the clip's.
  final List<List<(double, String)>> _marks;

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

  /// The playhead in [state]'s clip, in seconds; in a blend state, the share
  /// of the cycle, nought to one.
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
    _passed.clear();
    final root = rootNode;
    final travelled = root == null ? null : _travel(root, _current, _head);
    final fadedFrom = root == null || _previous < 0
        ? null
        : _travel(root, _previous, _previousHead);
    final before = _cycles(_current, _head);
    _head = _advance(_current, _head, step);
    _pass(_current, before, _cycles(_current, _head));
    if (_previous >= 0) {
      _previousHead = _advance(_previous, _previousHead, step);
      _fadeElapsed += step;
    }
    rootDelta.setZero();
    if (root != null) {
      rootDelta.setFrom(_travel(root, _current, _head)..sub(travelled!));
      if (_previous >= 0) {
        final w = (_fadeElapsed / _fadeDuration).clamp(0.0, 1.0);
        final faded = _travel(root, _previous, _previousHead)..sub(fadedFrom!);
        rootDelta
          ..scale(w)
          ..addScaled(faded, 1.0 - w);
      }
      rootDelta.y = 0.0;
    }
    if (_previous >= 0 && _fadeElapsed >= _fadeDuration) _previous = -1;
    if (_previous < 0) _takeTransition();
    _sample();
    if (root != null) {
      pose.translations[root * 3] = _rest.translations[root * 3];
      pose.translations[root * 3 + 2] = _rest.translations[root * 3 + 2];
    }
    for (final layer in layers) {
      layer._step(step);
      final over = layer.graph.evaluate(step);
      if (over.nodeCount != pose.nodeCount) {
        throw ArgumentError(
          'A layer of ${over.nodeCount} nodes over a graph of '
          '${pose.nodeCount}: a layer animates the same skeleton.',
        );
      }
      if (layer.weight > 0.0) layer._layOnto(pose);
    }
    for (final goal in goals) {
      goal
        ..step(step)
        ..apply(pose);
    }
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
    final plays = _clips[state];
    if (plays.blend) return _advanceBlend(state, plays, head, step);
    final length = plays.clips.first.duration;
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

  /// A blend's phase moves by the length its mix would have: see
  /// [AnimationBlendSpace]. Its elapsed time is counted in cycles already.
  _Playhead _advanceBlend(
    int state,
    _Plays plays,
    _Playhead head,
    double step,
  ) {
    final weights = _weightsOf(plays);
    var length = 0.0;
    for (var i = 0; i < weights.length; i++) {
      length += plays.clips[i].duration * weights[i];
    }
    final delta = step * machine.states[state].speed;
    if (length <= 0.0 || delta == 0.0) {
      return _Playhead(
        head.time,
        head.elapsed + (length <= 0.0 ? 1.0 : 0.0),
        head.reversing,
      );
    }
    final share = delta / length;
    final moved = advanceTime(
      time: head.time,
      deltaSeconds: share,
      length: 1.0,
      wrap: machine.states[state].wrap,
      reversing: head.reversing,
    );
    return _Playhead(moved.time, head.elapsed + share, moved.reversing);
  }

  /// How much of each of a blend's clips plays now, summing to one, into
  /// the blend's own list: along a line, the two its parameter falls
  /// between; across a plane, every point by the inverse square of its
  /// distance — all of one standing on it, smoothly between.
  List<double> _weightsOf(_Plays plays) {
    final w = plays.weights..fillRange(0, plays.weights.length, 0.0);
    final value = parameters.valueAt(plays.parameter);
    final at = plays.at;
    if (plays.parameterY >= 0) {
      final across = parameters.valueAt(plays.parameterY);
      var sum = 0.0;
      for (var i = 0; i < at.length; i++) {
        final dx = value - at[i], dy = across - plays.ys[i];
        final d2 = dx * dx + dy * dy;
        if (d2 < 1e-12) {
          w.fillRange(0, w.length, 0.0);
          w[i] = 1.0;
          return w;
        }
        w[i] = 1.0 / d2;
        sum += w[i];
      }
      for (var i = 0; i < w.length; i++) {
        w[i] /= sum;
      }
      return w;
    }
    if (value <= at.first) {
      w[0] = 1.0;
      return w;
    }
    if (value >= at.last) {
      w[at.length - 1] = 1.0;
      return w;
    }
    var i = 0;
    while (value > at[i + 1]) {
      i++;
    }
    final t = (value - at[i]) / (at[i + 1] - at[i]);
    w[i] = 1.0 - t;
    w[i + 1] = t;
    return w;
  }

  /// How far [root] has come since [state] was entered, by its clips'
  /// translation tracks unwound across the loop's turns: where the clip has
  /// it now, plus a whole cycle's travel for each turn already gone round.
  Vector3 _travel(int root, int state, _Playhead head) {
    final plays = _clips[state];
    if (!plays.blend) {
      final clip = plays.clips.first;
      final length = clip.duration;
      // The turns the playhead has wrapped, read off the playhead itself:
      // elapsed is the time and the whole cycles before it. Floored from
      // elapsed alone, a sum of steps a hair short of the turn counted one
      // fewer than the playhead had wrapped, and the root leapt a stride back.
      final turns =
          length <= 0.0 || machine.states[state].wrap != AnimationWrap.loop
          ? 0
          : ((head.elapsed - head.time) / length).round();
      return _unwound(clip, root, head.time, turns);
    }
    final weights = _weightsOf(plays);
    final turns = machine.states[state].wrap == AnimationWrap.loop
        ? (head.elapsed - head.time).round()
        : 0;
    final out = Vector3.zero();
    for (var i = 0; i < weights.length; i++) {
      if (weights[i] == 0.0) continue;
      final c = plays.clips[i];
      out.addScaled(
        _unwound(c, root, head.time * c.duration, turns),
        weights[i],
      );
    }
    return out;
  }

  /// [clip]'s [root] translation at [time], after [turns] whole cycles.
  Vector3 _unwound(AnimationClip clip, int root, double time, int turns) {
    final track = _rootTrack(clip, root);
    if (track == null) return Vector3.zero();
    track.sample(time, _sampled);
    final at = Vector3(_sampled[0], _sampled[1], _sampled[2]);
    if (turns == 0) return at;
    track.sample(track.endTime, _sampled);
    final end = Vector3(_sampled[0], _sampled[1], _sampled[2]);
    track.sample(track.startTime, _sampled);
    final start = Vector3(_sampled[0], _sampled[1], _sampled[2]);
    return at..addScaled(end - start, turns.toDouble());
  }

  AnimationTrack? _rootTrack(AnimationClip clip, int root) {
    for (final track in clip.tracks) {
      if (track.nodeIndex == root &&
          track.path == AnimationPath.translation &&
          track.pointer == null) {
        return track;
      }
    }
    return null;
  }

  final Float32List _sampled = Float32List(3);

  /// How many cycles of [state] [head] has gone through since it was
  /// entered; null for a clip with no length, which has no cycle to mark.
  double? _cycles(int state, _Playhead head) {
    final plays = _clips[state];
    if (plays.blend) return head.elapsed;
    final length = plays.clips.first.duration;
    return length <= 0.0 ? null : head.elapsed / length;
  }

  /// [state]'s markers between [from] and [to] cycles: each share m of a
  /// cycle n passed when from ≤ n + m < to, so one on a boundary is passed
  /// once and one at nought as the state is entered. A clip played once has
  /// one cycle to pass.
  void _pass(int state, double? from, double? to) {
    if (from == null || to == null || !(to > from)) return;
    final marks = _marks[state];
    if (marks.isEmpty) return;
    final once = machine.states[state].wrap == AnimationWrap.once;
    final last = once ? 0 : to.floor();
    for (var n = from.floor(); n <= last; n++) {
      for (final (share, name) in marks) {
        final at = n + share;
        if (from <= at && at < to) {
          _passed.add((state: machine.states[state].name, name: name));
        }
      }
    }
  }

  /// A clip with no length is a single pose, done as soon as it is entered.
  double _normalized(int state, _Playhead head) {
    final plays = _clips[state];
    if (plays.blend) return head.elapsed;
    final length = plays.clips.first.duration;
    return length <= 0.0 ? 1.0 : head.elapsed / length;
  }

  void _sample() {
    _sampleState(_current, _head, pose);
    if (_previous < 0) return;
    _sampleState(_previous, _previousHead, _from);
    pose.blendFrom(_from, fadeWeight);
  }

  /// [state] at [head] into [into]: its clip, or its blend's two.
  void _sampleState(int state, _Playhead head, Pose into) {
    final plays = _clips[state];
    if (!plays.blend) {
      into.sampleClip(plays.clips.first, head.time);
      return;
    }
    // Each clip with a share, mixed into what came before by its share of
    // the running total: an average of poses one at a time.
    final weights = _weightsOf(plays);
    var total = 0.0;
    for (var i = 0; i < weights.length; i++) {
      final w = weights[i];
      if (w == 0.0) continue;
      final c = plays.clips[i];
      if (total == 0.0) {
        into.sampleClip(c, head.time * c.duration);
      } else {
        _scratch.sampleClip(c, head.time * c.duration);
        into.blendFrom(_scratch, total / (total + w));
      }
      total += w;
    }
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

/// A graph of its own over part of a skeleton, laid on another's pose — the
/// layers of N1: a reload over a run, a flinch over a walk, a look over
/// whatever the body is doing.
///
/// Its own [graph], with its own states and parameters, is evaluated on the
/// same steps as the one it is laid on, and where its [mask] covers a node
/// it is mixed in by [weight]:
///
/// * [AnimationBlend.override] replaces the base's value, faded by [weight].
///   The mask says where it writes, and it writes there whether or not its
///   clip has a track for the node; a mask is chosen to match the clips.
/// * [AnimationBlend.additive] lays the layer's distance from the
///   skeleton's rest on top of the base: a breath, a recoil, a lean — clips
///   authored as a difference from rest rather than as a pose.
///
/// [weight] moves when told to by [fadeTo], on the same steps, so a layer
/// comes in and goes out without a pop.
final class AnimationGraphLayer {
  AnimationGraphLayer({
    required this.graph,
    AnimationMask? mask,
    this.blend = AnimationBlend.override,
    double weight = 1.0,
  }) : mask = mask ?? AnimationMask.everything,
       _weight = weight.clamp(0.0, 1.0),
       _target = weight.clamp(0.0, 1.0);

  final AnimationGraph graph;
  AnimationMask mask;
  AnimationBlend blend;

  double _weight;
  double _target;
  double _rate = 0.0;
  Pose? _rest;

  /// How much of this layer is laid on, nought to one.
  double get weight => _weight;

  set weight(double value) {
    _weight = value.clamp(0.0, 1.0);
    _target = _weight;
    _rate = 0.0;
  }

  /// Moves [weight] to [target] over [seconds] of steps; at once for none.
  void fadeTo(double target, double seconds) {
    _target = target.clamp(0.0, 1.0);
    if (seconds <= 0.0) {
      weight = _target;
      return;
    }
    _rate = (_target - _weight).abs() / seconds;
  }

  void _step(double dt) {
    if (_rate == 0.0) return;
    final move = _rate * dt;
    if ((_target - _weight).abs() <= move) {
      _weight = _target;
      _rate = 0.0;
    } else {
      _weight += _target > _weight ? move : -move;
    }
  }

  /// This layer's pose into [base], where its mask covers, by [weight].
  void _layOnto(Pose base) {
    final over = graph.pose;
    final w = _weight;
    final additive = blend == AnimationBlend.additive;
    final rest = additive ? (_rest ??= over.restCopy()) : null;
    for (var node = 0; node < base.nodeCount; node++) {
      if (!mask.covers(node)) continue;
      final t = node * 3, r = node * 4;
      for (var k = 0; k < 3; k++) {
        if (rest == null) {
          base.translations[t + k] +=
              (over.translations[t + k] - base.translations[t + k]) * w;
          base.scales[t + k] += (over.scales[t + k] - base.scales[t + k]) * w;
        } else {
          base.translations[t + k] +=
              (over.translations[t + k] - rest.translations[t + k]) * w;
          final from = rest.scales[t + k];
          if (from != 0.0) {
            base.scales[t + k] *= 1.0 + (over.scales[t + k] / from - 1.0) * w;
          }
        }
      }
      final mine = Quaternion(
        base.rotations[r],
        base.rotations[r + 1],
        base.rotations[r + 2],
        base.rotations[r + 3],
      );
      final theirs = Quaternion(
        over.rotations[r],
        over.rotations[r + 1],
        over.rotations[r + 2],
        over.rotations[r + 3],
      );
      final Quaternion mixed;
      if (rest == null) {
        mixed = shortestArcSlerp(mine, theirs, w);
      } else {
        // The layer's turn from rest, in the node's own frame, laid after
        // the base's: base · slerp(1, rest⁻¹ · layer, w).
        final at = Quaternion(
          rest.rotations[r],
          rest.rotations[r + 1],
          rest.rotations[r + 2],
          rest.rotations[r + 3],
        );
        final delta = at.conjugated() * theirs;
        mixed = mine * shortestArcSlerp(Quaternion.identity(), delta, w)
          ..normalize();
      }
      base.rotations[r] = mixed.x;
      base.rotations[r + 1] = mixed.y;
      base.rotations[r + 2] = mixed.z;
      base.rotations[r + 3] = mixed.w;
    }
  }
}

/// What a state plays: one clip, or a blend's clips at their points by a
/// parameter.
final class _Plays {
  _Plays.one(AnimationClip clip)
    : clips = <AnimationClip>[clip],
      at = const <double>[],
      ys = const <double>[],
      parameter = -1,
      parameterY = -1,
      weights = <double>[1.0],
      blend = false;

  _Plays.blend(
    this.parameter,
    this.at,
    this.clips, {
    this.parameterY = -1,
    this.ys = const <double>[],
  }) : weights = List<double>.filled(clips.length, 0.0),
       blend = true;

  final List<AnimationClip> clips;
  final List<double> at;
  final List<double> ys;
  final int parameter;

  /// The second parameter of a blend across a plane; -1 along a line.
  final int parameterY;

  /// Each clip's share, rewritten by every reading.
  final List<double> weights;
  final bool blend;
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
