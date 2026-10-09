import 'package:flutter3d_physics/flutter3d_physics.dart';
import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';

import 'run_part.dart';

/// A [Demo] being written while the run is played: the tape, the
/// checkpoints, and `HR3`'s levels swapped in under it.
///
/// **What used to be five fields in every game's widget.** Each game kept a
/// start, a level, a hash, a trace and a recorder beside each other and
/// assembled the [Demo] at the end; a level swapped in mid-run had nowhere to
/// go, so the platformer threw its demo away at every edit and began another.
/// The swap has to touch the trace and the list of swaps together, at a step
/// counted in this tape rather than the timeline's, and that is one object's
/// job.
final class DemoRecording {
  DemoRecording({
    required this.level,
    required this.levelHash,
    required this.start,
    required int seed,
    int checkpointEvery = 25,
    this.simulation = SimulationVersion.engineOnly,
    this.bodies,
    int poseEvery = 4,
    double stepSeconds = 1.0 / 60.0,
    this.physics = const DartPhysics(),
  }) : recorder = InputTapeRecorder(seed: seed),
       checkpoints = DigestTrace(every: checkpointEvery),
       poses = PoseRecorder(every: poseEvery, stepSeconds: stepSeconds);

  /// The physics the run is played on — its world's backend
  /// (`CollisionWorld.backend`) — named in the file (`Demo.physics`) so a
  /// replay on another refuses rather than diverges.
  final PhysicsBackend physics;

  /// The simulation the run is played in — the genre's constant, such as
  /// `platformerSimulation` — written into the file so that a build on
  /// another one refuses the tape rather than replaying it wrong.
  final SimulationVersion simulation;

  /// Where the run's bodies are now, asked every [PoseRecorder.every] steps
  /// by [observe] for the pose record written beside the tape; null records
  /// none. Named bodies, each a place and a rotation.
  final Iterable<BodyPose> Function()? bodies;

  /// The pose record being written: what plays on a build whose simulation
  /// differs from [simulation].
  final PoseRecorder poses;

  /// The asset path of the level the run started in.
  final String level;

  /// [Level.digestHex] of that level as it was loaded.
  final String levelHash;

  /// The state the tape starts from.
  final Snapshot start;

  /// Where the loop writes each step's input. Add it to `EngineLoop.recorders`.
  final InputTapeRecorder recorder;

  /// A digest every so many steps, taken live.
  final DigestTrace checkpoints;

  final List<DemoLevelSwap> _swaps = <DemoLevelSwap>[];

  /// How many steps have been recorded.
  int get steps => recorder.tape.steps;

  /// Takes a checkpoint if the step just run is one. Call after every step;
  /// [after] is asked for the state the step left only on a checkpoint step,
  /// since a save of every body is what a checkpoint costs.
  ///
  /// The pose record is taken here too, on its own steps, from [bodies].
  void observe(Snapshot Function() after) {
    final step = recorder.tape.steps;
    if (step % checkpoints.every == 0) {
      checkpoints.observe(step, after().toJson());
    }
    final bodies = this.bodies;
    if (bodies != null && poses.due(step)) poses.record(step, bodies());
  }

  /// Writes down that [next] was put under the run [stepsAgo] steps before
  /// the present — `RunTimeline.swapLevel`'s step, counted back from now,
  /// since the timeline and this tape did not start at the same step.
  ///
  /// The swap replaced the run from there on, so a swap already written at
  /// or after that step is dropped with the checkpoints taken after it: both
  /// describe a run that was lived again.
  ///
  /// False, and nothing written, when the swap took effect before this
  /// recording began. The start this recording holds was then made by the
  /// old level and the run since by the new one, and no file can say that;
  /// the caller begins a new recording from the present instead and writes
  /// the swap at its step zero.
  bool levelSwapped(Level next, {required int stepsAgo}) {
    final at = recorder.tape.steps - stepsAgo;
    if (at < 0) return false;
    _swaps
      ..removeWhere((swap) => swap.step >= at)
      ..add(DemoLevelSwap(step: at, level: next));
    checkpoints.forgetAfter(at);
    poses.forgetAfter(at);
    _loopChanges.removeWhere((change) => change.step > at);
    _events?.forgetAfter(at - 1);
    return true;
  }

  final List<LoopChange> _loopChanges = <LoopChange>[];
  EventTrace? _events;
  EngineLoop? _loop;
  List<Registration> _observers = const <Registration>[];

  /// Records through [loop]: its input into [recorder], each step's event
  /// digest, and every change the loop journals — plugins switched, the
  /// time scale, the step rate — at the step of this tape it was made at.
  ///
  /// **The plugins' state is written first, at the step recording begins**,
  /// since the loop may have been running and switching for a while, and a
  /// replay starts from the engine's defaults. So is a time scale other than
  /// one. Steps run again after a rollback are not recorded twice: the loop
  /// marks them resimulated and the recorder skips them.
  void attach(EngineLoop loop) {
    if (_loop != null) {
      throw StateError('a recording is attached to one loop at a time');
    }
    _loop = loop;
    _events = EventTrace();
    loop.recorders.add(recorder);
    _observers = <Registration>[
      loop.onStepEnd(_observeStep),
      loop.onChange(_observeChange),
    ];
    final at = recorder.tape.steps;
    if (loop.plugins.order.isNotEmpty) {
      _loopChanges.add(LoopPluginChange(loop.plugins.stateAt(at)));
    }
    if (loop.timeScale != 1.0) {
      _loopChanges.add(LoopTimeScale(step: at, scale: loop.timeScale));
    }
  }

  /// Stops recording through the loop [attach] was given.
  void detach() {
    final loop = _loop;
    if (loop == null) return;
    loop.recorders.remove(recorder);
    for (final observer in _observers) {
      observer.cancel();
    }
    _observers = const <Registration>[];
    _loop = null;
  }

  void _observeStep(StepEventSummary summary) {
    if (summary.resimulated) return;
    // The recorder wrote this step's entry before it ran, so it is the last.
    _events?.observe(
      recorder.tape.steps - 1,
      count: summary.count,
      digest: summary.digest,
    );
  }

  // Made at the boundary, before the step's entry is written: the change
  // takes effect before the step at the tape's present length.
  void _observeChange(LoopChange change) =>
      _loopChanges.add(change.at(recorder.tape.steps));

  /// The run so far, as a file.
  Demo demo({
    required String buildStamp,
    String? platform,
    String? recordedBy,
  }) => Demo(
    level: level,
    levelHash: levelHash,
    start: start,
    tape: recorder.tape,
    buildStamp: buildStamp,
    checkpoints: checkpoints,
    platform: platform,
    recordedBy: recordedBy,
    levelSwaps: List<DemoLevelSwap>.unmodifiable(_swaps),
    // What it replays on: see `Demo.physics`.
    physics: physics.name,
    loopChanges: List<LoopChange>.unmodifiable(_loopChanges),
    events: _events,
    simulation: simulation,
    poses: bodies == null ? null : poses.recorded,
  );
}

/// What [replayDemoOnLoop] found.
final class DemoReplay {
  const DemoReplay({
    required this.steps,
    this.divergence,
    this.eventDivergence,
  });

  /// How many steps were played.
  final int steps;

  /// The first checkpoint the replay did not match, or null when it matched
  /// every one the file holds.
  final Divergence? divergence;

  /// The first step whose events differed from the file's, or null when
  /// every step published what it did when recorded — or the file has no
  /// event trace. Only [replayDemoOnLoop] fills it.
  final EventDivergence? eventDivergence;
}

/// Plays [demo] through [loop] from its start: the file's loop changes are
/// made at their steps, and each step's events are compared with the file's
/// as well as its checkpoints.
///
/// **Through the loop's snapshots, the one path.** The run the tape recorded
/// is the loop's part [part] — a genre under its plugin id
/// (`PlatformerPlugin.id`), a game's own run under the `SnapshotPart` it
/// registered — and the file's start, which is that run's own snapshot, is
/// restored as that part alone (`EngineLoop.rewindTo(0, state: …)`); each
/// checkpoint is digested from the part's data in the loop's capture, so a
/// tape recorded from the run's own `save()` checks out as it always did. The
/// tape plays through the loop's own systems, which must be the simulation
/// the run was recorded with; plugins the file switched are switched at the
/// same steps, so the run arrives where it did. The live devices are muted
/// while it plays.
///
/// The level [Demo.level] names must be up when this is called; [swapLevel]
/// puts a swapped document in its place and must carry the run over, as the
/// game did live. It is required exactly when the demo has swaps in it. A
/// swap at step K goes in after the checkpoint at K is compared, which is the
/// order the live run met them in.
///
/// Given [simulation] — the one this build runs — a run recorded on another
/// is refused before a step is played: [ReplayException] says why and carries
/// the run's pose record, which a viewer plays instead.
///
/// Given [actions] — the game's declared [ActionSet] — a tape recorded
/// before the game read an axis where it once read two buttons is upgraded
/// first (`ActionSet.upgradeTape`), so an old run replays as it was played.
///
/// Throws an [ArgumentError] when [part] is not one of the loop's parts.
DemoReplay replayDemoOnLoop({
  required Demo demo,
  required EngineLoop loop,
  required String part,
  void Function(Level level)? swapLevel,
  SimulationVersion? simulation,
  ActionSet? actions,
}) {
  if (simulation != null) demo.checkSimulation(simulation);
  if (demo.levelSwaps.isNotEmpty && swapLevel == null) {
    throw ArgumentError.value(
      demo,
      'demo',
      'replaces its level at step ${demo.levelSwaps.first.step}, and no '
          'swapLevel was given to replace it with',
    );
  }
  final start = loopStateWith(loop, part, demo.start);
  final expected = <int, int>{
    for (var i = 0; i < demo.checkpoints.steps.length; i++)
      demo.checkpoints.steps[i]: demo.checkpoints.digests[i],
  };
  final swaps = demo.levelSwaps;
  var nextSwap = 0;
  void swapAt(int step) {
    while (nextSwap < swaps.length && swaps[nextSwap].step == step) {
      swapLevel!(swaps[nextSwap++].level);
    }
  }

  final trace = EventTrace();
  var played = 0;
  void observe(StepEventSummary summary) {
    if (summary.resimulated) return;
    trace.observe(played, count: summary.count, digest: summary.digest);
  }

  loop
    ..rewindTo(0, state: start)
    ..schedule(demo.loopChanges);
  swapAt(0);
  final playback = InputTapePlayback(demo.tape, actions: actions);
  final previous = loop.playback;
  final wasMuted = loop.input.muted;
  loop.playback = playback;
  final observer = loop.onStepEnd(observe);
  loop.input.muted = true;
  Divergence? divergence;
  try {
    while (!playback.isFinished) {
      loop.runSteps(1);
      played++;
      final digest = expected[played];
      if (digest != null && divergence == null) {
        final found = StateDigest.of(runStateIn(loop.capture(), part).toJson());
        if (found != digest) {
          divergence = Divergence(step: played, expected: digest, found: found);
        }
      }
      swapAt(played);
    }
  } finally {
    loop.playback = previous;
    observer.cancel();
    loop.input.muted = wasMuted;
  }
  final unreached = demo.checkpoints.steps.where((s) => s > played).firstOrNull;
  final recordedEvents = demo.events;
  return DemoReplay(
    steps: played,
    divergence:
        divergence ??
        (unreached == null
            ? null
            : Divergence(
                step: unreached,
                expected: expected[unreached],
                found: null,
              )),
    eventDivergence: recordedEvents == null
        ? null
        : trace.divergenceFrom(recordedEvents, through: played - 1),
  );
}
