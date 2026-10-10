import '../input/input_state.dart';
import '../input/input_tape.dart';
import '../loop/engine_loop.dart';
import 'entity_tracks.dart';
import 'first_differing_path.dart';
import 'snapshot.dart';
import 'state_digest.dart';

/// One side of a comparison: a simulation, the state it starts from and the
/// tape it plays, able to answer what the state was after any number of
/// steps.
///
/// **Forward only, with the states it has been asked for kept.** A
/// simulation cannot step backwards, so reaching step 40 after step 90
/// restores the nearest kept state at or before 40 and plays on from there.
/// Bisection asks for a handful of states, each between two it already has,
/// so the work is a couple of passes over the bracket rather than one per
/// probe.
///
/// **Each side owns its live objects.** A side remembers where it left them
/// so it can play on rather than restore; two sides stepping one simulation
/// would each find it where the other left it. Comparing two tapes on one
/// build means two instances of the simulation, which is also what keeps
/// the two runs from sharing anything by accident.
///
/// **Through a loop, where there is one** ([ReplaySide.loop]): the states
/// are the loop's captures, put back with `EngineLoop.rewindTo` and played
/// on by the loop's own tape playback, so every part of the state a plugin
/// added is compared and restored, and the step count the systems read is
/// the side's. A run that steps itself goes through a [RunLoop]. The
/// constructor with three functions is the form for a simulation with no
/// loop.
final class ReplaySide {
  ReplaySide({
    required this.start,
    required this.tape,
    required this.input,
    required this.step,
    required this.restore,
    required this.capture,
  }) : loop = null,
       _kept = <int, Snapshot>{0: start};

  /// A side played through [loop], from [start] — a capture of [loop];
  /// the loop as it is now when left out.
  ///
  /// The loop is this side's alone: nothing else steps it while the side is
  /// asked questions, and it records nothing (its `recorders` are not
  /// written while the side plays).
  ReplaySide.loop(EngineLoop this.loop, {required this.tape, Snapshot? start})
    : start = start ?? loop.capture(),
      input = loop.input,
      step = (() => loop.runSteps(1)),
      restore = loop.restore,
      capture = loop.capture,
      _kept = <int, Snapshot>{} {
    _kept[0] = this.start;
  }

  /// The loop this side plays through; null for a side made of functions.
  final EngineLoop? loop;

  /// The state before the first step.
  final Snapshot start;

  /// One entry per step, played into [input] before each.
  final InputTape tape;

  final InputState input;

  /// Runs one fixed step of this side's simulation.
  final void Function() step;

  /// Puts a snapshot back into this side's live objects.
  final void Function(Snapshot snapshot) restore;

  /// Writes this side's live objects down.
  final Snapshot Function() capture;

  final Map<int, Snapshot> _kept;

  /// How many steps the live objects have taken since [start], or null when
  /// they have not been restored by this side yet.
  int? _at;

  /// How many steps this side has run, over every question asked of it —
  /// what a test reads to see that bisection is cheaper than walking.
  int stepsRun = 0;

  /// The state after [steps] steps of [tape]; `stateAfter(0)` is [start].
  Snapshot stateAfter(int steps) {
    assert(steps >= 0 && steps <= tape.steps, 'the tape has ${tape.steps}');
    final kept = _kept[steps];
    if (kept != null) return kept;
    final from = _kept.keys.where((k) => k <= steps).reduce(_max);
    final at = _at;
    final resume = at != null && at >= from && at <= steps ? at : from;
    final playback = InputTapePlayback(
      InputTape(seed: tape.seed, frames: tape.frames.sublist(resume, steps)),
    );
    final wasMuted = input.muted;
    input.muted = true;
    try {
      if (loop case final loop?) {
        if (resume != at) loop.rewindTo(resume, state: _kept[resume]);
        final recorders = List.of(loop.recorders);
        final previous = loop.playback;
        loop
          ..recorders.clear()
          ..playback = playback;
        try {
          loop.runSteps(steps - resume);
          stepsRun += steps - resume;
        } finally {
          loop
            ..playback = previous
            ..recorders.addAll(recorders);
        }
      } else {
        if (resume != at) restore(_kept[resume]!);
        while (!playback.isFinished) {
          playback.applyTo(input);
          input.beginStep();
          step();
          input.endStep();
          stepsRun++;
        }
      }
    } finally {
      input.muted = wasMuted;
    }
    _at = steps;
    return _kept[steps] = capture();
  }

  static int _max(int a, int b) => a > b ? a : b;
}

/// What [bisectTapes] found.
sealed class TapeBisection {
  const TapeBisection();

  Map<String, Object?> toJson();
}

/// The two runs were the same state after every step both tapes have.
final class TapesAgree extends TapeBisection {
  const TapesAgree({
    required this.steps,
    required this.stepsA,
    required this.stepsB,
  });

  /// How many steps were compared: the shorter tape's length.
  final int steps;

  final int stepsA;
  final int stepsB;

  @override
  Map<String, Object?> toJson() => <String, Object?>{
    'agree': true,
    'steps': steps,
    'stepsA': stepsA,
    'stepsB': stepsB,
  };

  @override
  String toString() => stepsA == stepsB
      ? 'the runs agree for all $steps steps'
      : 'the runs agree for the $steps steps both have; one tape has '
            '${stepsA > stepsB ? stepsA - stepsB : stepsB - stepsA} more';
}

/// The first step after which the two runs were different states.
final class TapesDiverge extends TapeBisection {
  const TapesDiverge({
    required this.step,
    required this.inputsDiffer,
    required this.path,
    required this.expected,
    required this.found,
    required this.components,
    required this.probes,
  });

  /// After this many steps the states differ, and after one fewer they were
  /// the same. Zero when the two runs started from different states; else
  /// the tape entry that made the difference is `step - 1`.
  final int step;

  /// Whether the two tapes hold different input for that entry. True points
  /// at the input — a different recording; false at the code or the
  /// platform, since the same state and the same input led somewhere else.
  final bool inputsDiffer;

  /// The first differing value, as `firstDifferingPath` spells it: under the
  /// entity and component when an [EntityLayout] was given and found one
  /// (`7.Health.hp`), into the raw snapshot otherwise (`random`).
  final String path;

  final Object? expected;
  final Object? found;

  /// Every entity component that differs at [step], in order; empty when no
  /// layout was given or the difference is outside the entities.
  final List<EntityComponent> components;

  /// How many steps were compared on the way: the cost of the answer.
  final int probes;

  /// The first differing component, or null when [components] is empty.
  EntityComponent? get component =>
      components.isEmpty ? null : components.first;

  @override
  Map<String, Object?> toJson() => <String, Object?>{
    'agree': false,
    'step': step,
    'inputsDiffer': inputsDiffer,
    'path': path,
    'expected': expected,
    'found': found,
    'components': <Map<String, Object?>>[
      for (final component in components) component.toJson(),
    ],
    'probes': probes,
  };

  @override
  String toString() {
    final cause = step == 0
        ? 'the runs start from different states'
        : 'step ${step - 1} ${inputsDiffer ? 'had different input' : 'had the same input'}';
    return '$cause; first at `$path`: $expected against $found';
  }
}

/// The first step after which [a] and [b] are different states, found by
/// bisection, and what differs there.
///
/// **Digests on the way, full snapshots once.** Each probe compares two
/// [StateDigest]s, and only the final step is read field by field. Comparing
/// the states is the part a run pays for per entity, so bisecting a
/// thousand-step bracket costs ten comparisons instead of a thousand, and
/// the stepping stays within twice the bracket (see [ReplaySide]).
///
/// [agreedAt] and [differsAt] bracket the search when something already
/// narrowed it — two [DigestTrace]s through [bracketFromTraces], say. Both
/// are checked rather than trusted: a bracket that does not hold is widened
/// to the start and to the end of the shorter tape.
///
/// **What "first" means.** The answer is a step after which the runs differ
/// with the step before it agreeing: a real point where the same state went
/// two ways. Runs that part, meet again and part later are found at one of
/// the partings, the first unless the meeting falls between probes — the
/// search can only be sure of the step it names.
///
/// [layout] names the entity and component that differ; without one the path
/// is into the raw snapshot.
TapeBisection bisectTapes({
  required ReplaySide a,
  required ReplaySide b,
  EntityLayout? layout,
  int agreedAt = 0,
  int? differsAt,
}) {
  final limit = a.tape.steps < b.tape.steps ? a.tape.steps : b.tape.steps;
  var probes = 0;
  bool same(int steps) {
    probes++;
    return StateDigest.of(a.stateAfter(steps).data) ==
        StateDigest.of(b.stateAfter(steps).data);
  }

  var lo = agreedAt.clamp(0, limit);
  if (!same(lo)) {
    if (lo == 0 || !same(0)) return _diverge(a, b, 0, layout, probes);
    lo = 0;
  }
  var hi = (differsAt ?? limit).clamp(lo, limit);
  if (hi == lo || same(hi)) {
    lo = hi;
    hi = limit;
    if (hi == lo || same(hi)) {
      return TapesAgree(
        steps: limit,
        stepsA: a.tape.steps,
        stepsB: b.tape.steps,
      );
    }
  }
  while (hi - lo > 1) {
    final mid = lo + (hi - lo) ~/ 2;
    if (same(mid)) {
      lo = mid;
    } else {
      hi = mid;
    }
  }
  return _diverge(a, b, hi, layout, probes);
}

TapesDiverge _diverge(
  ReplaySide a,
  ReplaySide b,
  int step,
  EntityLayout? layout,
  int probes,
) {
  final left = a.stateAfter(step);
  final right = b.stateAfter(step);
  final components =
      layout?.differences(left, right) ?? const <EntityComponent>[];
  final first = components.isEmpty ? null : components.first;
  final differs = first == null
      ? firstDifferingPath(left.data, right.data)
      : _withPrefix(
          '${first.entity}.${first.component}',
          firstDifferingPath(
            layout!.entitiesOf(left)[first.entity]?[first.component],
            layout.entitiesOf(right)[first.entity]?[first.component],
          ),
        );
  final inputsDiffer =
      step > 0 &&
      StateDigest.of(a.tape.frames[step - 1].toJson()) !=
          StateDigest.of(b.tape.frames[step - 1].toJson());
  return TapesDiverge(
    step: step,
    inputsDiffer: inputsDiffer,
    path: differs?.path ?? '',
    expected: differs?.a,
    found: differs?.b,
    components: components,
    probes: probes,
  );
}

/// A component present on one side only reads as a whole-value difference
/// at the component itself, which `firstDifferingPath` reports with an empty
/// path under it.
({String path, Object? a, Object? b})? _withPrefix(
  String prefix,
  ({String path, Object? a, Object? b})? inner,
) => inner == null
    ? (path: prefix, a: null, b: null)
    : (
        path: inner.path.isEmpty
            ? prefix
            : inner.path.startsWith('[')
            ? '$prefix${inner.path}'
            : '$prefix.${inner.path}',
        a: inner.a,
        b: inner.b,
      );

/// The bracket two digest traces give [bisectTapes], in its own counting.
///
/// A trace's checkpoint at step `s` is taken after the step numbered `s` has
/// run (`DigestTrace.observe`), so it is the state after `s + 1` steps. The
/// bracket is the last checkpoint both traces agree on and the first they do
/// not; null when they never disagree.
({int agreedAt, int differsAt})? bracketFromTraces(
  DigestTrace a,
  DigestTrace b,
) {
  final divergence = a.divergenceFrom(b.digests);
  if (divergence == null) return null;
  final before = divergence.step - a.every;
  return (
    agreedAt: before < 0 ? 0 : before + 1,
    differsAt: divergence.step + 1,
  );
}
