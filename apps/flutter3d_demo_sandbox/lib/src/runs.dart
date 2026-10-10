/// The sandbox's runs, written down as they are played and played back from
/// the file: a tape of the walk, the look and the hands, the loop's journal
/// and each step's event digest (`DemoRecording.attach`), checkpoints of the
/// whole state, and where the body and every falling block went.
library;

import 'package:flutter3d_game/flutter3d_game.dart'
    show DemoFile, DemoRecording, DemoReplay, replayDemoOnLoop;
import 'package:flutter3d_physics_native/flutter3d_physics_native.dart'
    show usePhysics;
import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';

import 'staging.dart';

/// The run being recorded through [loop], and the file the last one went to.
///
/// **Recording starts at once and never stops**: a sandbox has no end, so a
/// run is whatever was played since the last [keep] or [replay], and keeping
/// it begins the next one from where the world stands. The world's own save
/// is another thing: the edits and where the body stood, kept between
/// launches; this is the play that made them.
final class SandboxRuns {
  SandboxRuns({
    required this.loop,
    required this.run,
    required this.file,
    this.buildStamp = 'dev',
    this.platform,
  }) {
    // The run as one part of the loop's snapshots: what [replay] restores a
    // file's start into and digests its checkpoints from, and what every
    // rewind of the loop covers.
    loop.snapshots.add(
      SnapshotPart.of(
        id: runPart,
        capture: () => run.state().data,
        restore: (Object? data, int _) {
          if (data is Map) run.restore(Snapshot(data.cast<String, Object?>()));
        },
      ),
    );
  }

  /// The id of the run's part of the loop's snapshots.
  static const String runPart = 'sandbox.run';

  final EngineLoop loop;
  final SandboxRun run;

  /// Where a kept run goes, and where [replay] reads it from.
  final DemoFile file;

  /// What the build calls itself in a run file.
  final String buildStamp;

  /// The platform a run is said to have been recorded on.
  final String? platform;

  DemoRecording? _recording;
  Registration? _observer;

  /// How many steps the run being recorded holds.
  int get steps => _recording?.steps ?? 0;

  /// Starts writing the run down from the state the world is in now. A run
  /// already being written is dropped.
  void begin() {
    _stop();
    final recording = DemoRecording(
      physics: usePhysics(),
      level: sandboxLevel,
      levelHash: sandboxLevelHash,
      start: run.state(),
      // The sandbox throws no dice: the seed is the hills'.
      seed: sandboxTerrain.seed,
      simulation: sandboxSimulation,
      bodies: run.poses,
    )..attach(loop);
    _recording = recording;
    _observer = loop.onStepEnd((StepEventSummary summary) {
      if (!summary.resimulated) recording.observe(run.state);
    });
  }

  /// The run so far, written to [file] and returned; the next one begins
  /// from here. Null when nothing is being recorded.
  Demo? keep() {
    final recording = _recording;
    if (recording == null) return null;
    final demo = recording.demo(buildStamp: buildStamp, platform: platform);
    // Not waited for: the run is in hand, and the file says what it could
    // not write through its own issues.
    file.write(demo).ignore();
    begin();
    return demo;
  }

  /// Plays the run [file] holds — or [demo] — from its start, and says
  /// whether it went where it went when it was recorded. The world is left
  /// where the run ended, and recording begins again from there.
  ///
  /// Throws [ReplayException] for a run recorded on another simulation; its
  /// pose record is what a viewer plays instead.
  Future<DemoReplay?> replay([Demo? demo]) async {
    final playing = demo ?? await file.read();
    if (playing == null) return null;
    _stop();
    try {
      return replayDemoOnLoop(
        demo: playing,
        loop: loop,
        part: runPart,
        simulation: sandboxSimulation,
      );
    } finally {
      loop.resetClock();
      begin();
    }
  }

  void _stop() {
    _observer?.cancel();
    _observer = null;
    _recording?.detach();
    _recording = null;
  }

  /// Stops recording.
  void dispose() => _stop();
}
