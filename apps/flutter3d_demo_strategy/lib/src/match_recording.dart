/// A match being written down: where it started, every order of every step,
/// a checkpoint every so often, and where the crowd stood.
///
/// **Out of the widget, so a test can write one.** These were five fields
/// on the screen's state and a block inside its frame, which nothing but the
/// running game could reach; the pose record is the reason they moved. A
/// `.f3drun` from the other genres carries one beside its tape, so a build
/// on other rules can still show the run it cannot replay, and a match had
/// none.
///
/// **And the loop's own record, as `DemoRecording.attach` writes it.** A
/// recording attached to the [EngineLoop] the match is stepped by keeps each
/// step's event digest and every change the loop journals — plugins switched,
/// the time scale, the step rate — at the step of the tape it was made at.
/// `DemoRecording` itself is not used: its tape is an `InputTape`, and this
/// genre's is an [OrderTape], which is why [MatchDemo] exists. [MatchDemo]
/// does not carry the two yet, so [RecordedMatch] writes them beside it under
/// the keys a `Demo` writes them under, `loopChanges` and `events`, which
/// [MatchDemo.fromJson] passes over.
library;

import 'package:flutter3d_foundation/flutter3d_foundation.dart';
import 'package:flutter3d_game_strategy/flutter3d_game_strategy.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart'
    show
        BodyPose,
        DemoFormatException,
        DigestTrace,
        EngineLoop,
        EventTrace,
        LoopChange,
        LoopPluginChange,
        LoopTimeScale,
        PoseRecorder,
        Snapshot,
        StepEventSummary;
import 'package:vector_math/vector_math.dart' show Quaternion;

import 'run.dart' show strategyStep;

/// How many steps apart the crowd's places are written: once a second.
///
/// **Every unit, and so not every few steps.** A runner is one body and the
/// other genres write it every four steps; a match is hundreds, walking at a
/// few metres a second under a camera fifty metres up, and a viewer drawing
/// it between two seconds' places draws the same picture at a fifteenth of
/// the file.
const int matchPoseEvery = 60;

/// Every unit standing on [simulation], each by its entity — the name a save
/// already gives it, and one a unit made later never shares with one that
/// died. A unit has no facing, so none is written.
Iterable<BodyPose> unitPoses(StrategySimulation simulation) => <BodyPose>[
  for (final Unit unit in simulation.units)
    BodyPose(
      'unit.${unit.entity.packed}',
      unit.position,
      Quaternion.identity(),
    ),
];

/// A match being recorded from the state [simulation] is in when this is
/// made. Its recorder hangs on the simulation's order queue until [stop].
final class MatchRecording {
  /// Starts writing [simulation] down, as the match on [level] — the map's
  /// asset — whose document digests to [levelHash].
  MatchRecording({
    required this.level,
    required this.levelHash,
    required StrategySimulation simulation,
  }) : start = simulation.save(),
       recorder = OrderTapeRecorder(seed: simulation.random.state) {
    simulation.orders.recorder = recorder;
  }

  /// The map's asset, and its document's digest.
  final String level;
  final String levelHash;

  /// The state the tape starts from.
  final Snapshot start;

  /// Every order of every step, hung on the simulation's queue.
  final OrderTapeRecorder recorder;

  /// A digest every so many steps, taken live.
  final DigestTrace checkpoints = DigestTrace();

  /// Where the crowd stood, every [matchPoseEvery] steps.
  final PoseRecorder poses = PoseRecorder(
    every: matchPoseEvery,
    stepSeconds: strategyStep,
  );

  /// How many steps are recorded.
  int get steps => recorder.tape.steps;

  final List<LoopChange> _loopChanges = <LoopChange>[];
  EventTrace? _events;
  EngineLoop? _loop;
  List<Registration> _observers = const <Registration>[];

  /// The changes the loop journalled while this recorded, each at the step
  /// of the tape it took effect before.
  List<LoopChange> get loopChanges =>
      List<LoopChange>.unmodifiable(_loopChanges);

  /// Each recorded step's event count and digest, or null when this was
  /// never [attach]ed.
  EventTrace? get events => _events;

  /// Records through [loop] as `DemoRecording.attach` does: each step's
  /// event digest, and every change the loop journals.
  ///
  /// **The plugins' state is written first, at the step recording begins**,
  /// and a time scale other than one, since the loop may have been running
  /// and switching for a while and a replay starts from the engine's
  /// defaults. A step run again after a rollback is not recorded twice.
  ///
  /// The orders are not taken from the loop: they hang on the simulation's
  /// queue, where the constructor put the recorder.
  void attach(EngineLoop loop) {
    if (_loop != null) {
      throw StateError('a recording is attached to one loop at a time');
    }
    _loop = loop;
    _events = EventTrace();
    _observers = <Registration>[
      loop.onStepEnd(_observeStep),
      loop.onChange(_observeChange),
    ];
    final at = steps;
    if (loop.plugins.order.isNotEmpty) {
      _loopChanges.add(LoopPluginChange(loop.plugins.stateAt(at)));
    }
    if (loop.timeScale != 1.0) {
      _loopChanges.add(LoopTimeScale(step: at, scale: loop.timeScale));
    }
  }

  /// Stops recording through the loop [attach] was given.
  void detach() {
    for (final observer in _observers) {
      observer.cancel();
    }
    _observers = const <Registration>[];
    _loop = null;
  }

  void _observeStep(StepEventSummary summary) {
    if (summary.resimulated) return;
    // The queue wrote this step's orders while it ran, so they are the last.
    _events?.observe(steps - 1, count: summary.count, digest: summary.digest);
  }

  // Made at the boundary, before the step's orders are written: the change
  // takes effect before the step at the tape's present length.
  void _observeChange(LoopChange change) => _loopChanges.add(change.at(steps));

  /// Takes the checkpoint and the poses due after the step just run.
  ///
  /// **Saved only on the steps a checkpoint is taken**: a save carries the
  /// world's core, and writing it out sixty times a second to keep one in
  /// twenty-five was a frame's worth of work thrown away. The poses likewise
  /// are gathered only when one is due.
  void observe(StrategySimulation simulation) {
    final step = steps;
    if (step % checkpoints.every == 0) {
      checkpoints.observe(step, simulation.save().toJson());
    }
    if (poses.due(step)) poses.record(step, unitPoses(simulation));
  }

  /// Takes the recorder off [simulation]'s queue, and off the loop.
  void stop(StrategySimulation simulation) {
    detach();
    if (identical(simulation.orders.recorder, recorder)) {
      simulation.orders.recorder = null;
    }
  }

  /// The match so far with the loop's record beside it: what is written to
  /// disk.
  RecordedMatch recorded({required String buildStamp, String? platform}) =>
      RecordedMatch(
        demo(buildStamp: buildStamp, platform: platform),
        loopChanges: loopChanges,
        events: _events,
      );

  /// The match so far, as a file, stamped [buildStamp] on [platform].
  MatchDemo demo({required String buildStamp, String? platform}) => MatchDemo(
    level: level,
    levelHash: levelHash,
    start: start,
    tape: recorder.tape,
    buildStamp: buildStamp,
    checkpoints: checkpoints,
    platform: platform,
    // So a build on other rules refuses the tape rather than replaying it
    // into a divergence — and shows these instead.
    simulation: strategySimulationVersion,
    poses: poses.recorded,
  );
}

/// A [MatchDemo] and the loop's record of the match: the changes the loop
/// journalled and each step's event digest, as a `Demo` carries them.
final class RecordedMatch {
  const RecordedMatch(
    this.demo, {
    this.loopChanges = const <LoopChange>[],
    this.events,
  });

  /// The match: its start, its order tape, checkpoints and poses.
  final MatchDemo demo;

  /// The loop's changes, by the step they took effect before.
  final List<LoopChange> loopChanges;

  /// Each step's event count and digest, or null when none were kept.
  final EventTrace? events;

  /// [demo]'s document, with `loopChanges` and `events` beside its fields.
  Map<String, Object?> toJson() => <String, Object?>{
    ...demo.toJson(),
    if (loopChanges.isNotEmpty)
      'loopChanges': <Map<String, Object?>>[
        for (final change in loopChanges) change.toJson(),
      ],
    if (events != null) 'events': events!.toJson(),
  };

  /// Reads a match, or throws a [DemoFormatException] that says why not. A
  /// file written before the loop's record was kept reads with none.
  factory RecordedMatch.fromJson(Map<String, Object?> json) {
    final demo = MatchDemo.fromJson(json);
    try {
      final List<LoopChange> changes = switch (json['loopChanges']) {
        null => const <LoopChange>[],
        final List<Object?> raw => <LoopChange>[
          for (final entry in raw) LoopChange.fromJson(entry),
        ],
        _ => throw const DemoFormatException('the loop changes are not a list'),
      };
      final EventTrace? events = switch (json['events']) {
        null => null,
        final Map<String, Object?> trace => EventTrace.fromJson(trace),
        _ => throw const DemoFormatException('the events are not a document'),
      };
      return RecordedMatch(demo, loopChanges: changes, events: events);
    } on Flutter3dFormatException catch (error) {
      throw DemoFormatException(error.message);
    }
  }
}
