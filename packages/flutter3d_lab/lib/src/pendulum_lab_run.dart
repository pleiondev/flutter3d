import 'package:flutter3d_sim/flutter3d_sim.dart';

import 'pendulum.dart';

const double labFixedDt = 1.0 / 60.0;

/// Runs [PendulumSimulation] for a fixed number of steps, recording exactly
/// what `edu-04` asks a virtual lab to record — a `DigestTrace` for
/// verification (`rp-01`'s own mechanism) and a `DataSourceTrace` of the one
/// parameter a student's panel changes (`edu-05`'s own mechanism, reused
/// rather than reinvented: a lab's length knob and a factory's temperature
/// sensor are both "a value with no controller behind it").
///
/// **Every per-step state is kept, not only the periodic checkpoints.** A
/// `DigestTrace` samples every `every` steps by design — cheap, and enough to
/// bracket a divergence — but branching a "what if" needs the *exact* state
/// at the step it branches from, which a sampled trace does not promise to
/// have. [stateAt] answers that from this run's own record, so a branch
/// resumes from precisely where the original was rather than from the
/// nearest checkpoint before it.
final class PendulumLabRun {
  factory PendulumLabRun({
    required double startLength,
    required int steps,
    double gravity = 9.81,
    double damping = 0.02,
    double startAngle = 0.6,
    int checkpointEvery = 25,
    double Function(int step, double currentLength)? lengthAt,
  }) {
    final pendulum = PendulumSimulation(
      lengthMeters: startLength,
      gravity: gravity,
      damping: damping,
      startAngle: startAngle,
    );
    return PendulumLabRun._resume(
      pendulum: pendulum,
      fromStep: 0,
      steps: steps,
      checkpointEvery: checkpointEvery,
      priorStates: <Map<String, Object?>>[Map<String, Object?>.of(pendulum.state)],
      lengthAt: lengthAt,
    );
  }

  /// The continuation half of a branch — resumes [pendulum] exactly as it
  /// stood after [fromStep], through [steps] more.
  factory PendulumLabRun._resume({
    required PendulumSimulation pendulum,
    required int fromStep,
    required int steps,
    required int checkpointEvery,
    required List<Map<String, Object?>> priorStates,
    double Function(int step, double currentLength)? lengthAt,
  }) {
    final checkpoints = DigestTrace(every: checkpointEvery);
    final lengths = DataSourceTrace();
    final states = List<Map<String, Object?>>.of(priorStates);

    for (var step = fromStep + 1; step <= steps; step++) {
      if (lengthAt != null) {
        pendulum.lengthMeters = lengthAt(step, pendulum.lengthMeters);
      }
      lengths.record(step, <String, Object?>{'length': pendulum.lengthMeters});
      pendulum.step(labFixedDt);
      checkpoints.observe(step, pendulum.state);
      states.add(Map<String, Object?>.of(pendulum.state));
    }

    return PendulumLabRun._(
      pendulum: pendulum,
      steps: steps,
      checkpoints: checkpoints,
      lengths: lengths,
      states: states,
    );
  }

  PendulumLabRun._({
    required this.pendulum,
    required this.steps,
    required this.checkpoints,
    required this.lengths,
    required List<Map<String, Object?>> states,
  }) : _states = List<Map<String, Object?>>.unmodifiable(states);

  final PendulumSimulation pendulum;
  final int steps;

  /// A digest every [PendulumSimulation]-agnostic `checkpointEvery` steps —
  /// what a divergence check compares two runs by.
  final DigestTrace checkpoints;

  /// The length this run read at every step — `edu-00` §9's "значение из
  /// источника... становится вводом для этого шага ленты", applied to a
  /// student's own panel rather than a broker.
  final DataSourceTrace lengths;

  final List<Map<String, Object?>> _states;

  /// The pendulum's exact state after [step] steps — `_states[0]` is the
  /// state before any step ran.
  Map<String, Object?> stateAt(int step) => _states[step];

  /// A "what if": a new run that starts from exactly where this one stood at
  /// [atStep] and continues through [throughStep] with [lengthAt] instead of
  /// whatever this run would have used — this run's own [pendulum],
  /// [checkpoints] and [lengths] are untouched, because [_resume] builds an
  /// entirely new [PendulumSimulation] rather than mutating this one's.
  PendulumLabRun branchAt(
    int atStep,
    int throughStep,
    double Function(int step, double currentLength) lengthAt,
  ) {
    if (atStep < 0 || atStep > steps) {
      throw ArgumentError.value(atStep, 'atStep', 'outside this run');
    }
    final at = _states[atStep];
    final branchPendulum = PendulumSimulation(
      lengthMeters: at['length']! as double,
      gravity: pendulum.gravity,
      damping: pendulum.damping,
      startAngle: at['theta']! as double,
    )..omega = at['omega']! as double;
    return PendulumLabRun._resume(
      pendulum: branchPendulum,
      fromStep: atStep,
      steps: throughStep,
      checkpointEvery: checkpoints.every,
      priorStates: _states.sublist(0, atStep + 1),
      lengthAt: lengthAt,
    );
  }

  /// Wraps this run as a genuine `.f3drun` — level and tape both real, if
  /// minimal: the lab has no brushes and the pendulum answers to no
  /// `GameAction`, so the level is a bare, named document and the tape is
  /// every step idle. Not a fabrication of the format: an idle tape and an
  /// empty level are exactly what a run with no controller and no geometry
  /// looks like, the same case [DataSourceTrace]'s own docstring already
  /// names — "a sensor reading has no action behind it."
  Demo toDemo({
    required String levelPath,
    required Level level,
    required String buildStamp,
  }) => Demo(
    level: levelPath,
    levelHash: level.digestHex,
    start: Snapshot(_states.first),
    tape: InputTape(
      seed: 0,
      frames: List<InputFrame>.generate(steps, (_) => const InputFrame()),
    ),
    buildStamp: buildStamp,
    checkpoints: checkpoints,
    dataSources: lengths,
  );
}
