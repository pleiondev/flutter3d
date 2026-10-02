import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_cpu/testing.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:flutter_test/flutter_test.dart';

import 'draw.dart';
import 'golden.dart';
import 'render_frame.dart';

/// What a game is handed to build the run a tape is replayed into.
final class ReplayStart {
  const ReplayStart({
    required this.demo,
    required this.input,
    required this.device,
  });

  /// The tape being replayed, for its level path and anything else the game
  /// wants to know before it loads.
  final Demo demo;

  /// The input the tape is played into, a step at a time.
  ///
  /// **The game has to read this one.** A simulation built with an
  /// [InputState] of its own steps against nobody's hands, stands still for
  /// the whole tape, and diverges at the first checkpoint for a reason that
  /// is about the test and not the game.
  final InputState input;

  /// Where the level's meshes and textures go: the software device every
  /// golden of this replay is drawn on.
  final GraphicsDevice device;
}

/// One run of a game, as a replay test drives it.
///
/// **An interface the game implements in its test, not one this package
/// implements for every genre.** A platformer, a racer and a strategy game
/// step, save and draw in their own ways, and the four calls below are the
/// whole of what a replay needs from any of them.
abstract interface class ReplaySubject {
  /// The `levelHash` of the level the run was built from — [Level.digestHex],
  /// or [contentDigestHex] of a genre's own document — or null when the game
  /// cannot say.
  ///
  /// Asked so that a level edited since the tape was recorded fails as that,
  /// rather than as a divergence at the first checkpoint, which reads as a
  /// bug in the simulation and sends whoever reads it looking there.
  String? get levelHash;

  /// Puts the run in the state the tape starts from.
  void restore(Snapshot start);

  /// Advances the run one fixed step of [dt] seconds, reading the input it
  /// was handed in [ReplayStart.input].
  void step(double dt);

  /// The whole state, the same snapshot the tape's checkpoints were taken of.
  Snapshot save();

  /// The scene and camera to draw at [step], once the run has reached it.
  ///
  /// May be asynchronous so that a game can wait for what it loads in the
  /// background — models a level names, which arrive a few frames after the
  /// level does — before the golden is drawn. A frame drawn before they
  /// arrived differs from one drawn after by how busy the machine was.
  FutureOr<FrameSubject> frame(int step);
}

/// Builds the run a tape is replayed into.
typedef ReplayStarter = FutureOr<ReplaySubject> Function(ReplayStart start);

/// Registers a test that replays the tape at [tapePath] and checks it.
///
///     void main() {
///       testReplay(
///         'test/tapes/ascent.f3drun',
///         start: Ascent.open,
///         goldensAt: <int>[120, 600],
///       );
///     }
///
/// A tape is a `.f3drun` — a [Demo] written with `jsonEncode(demo.toJson())`
/// — and the game's own recorder writes one whenever a level is played. The
/// replay runs on the software backend, so a game's CI needs no GPU, no
/// display and no driver to keep two promises:
///
/// * **[digestAt] says the simulation still does what it did.** At each step
///   named, the digest of [ReplaySubject.save] must equal the one the tape
///   recorded there. Null, the default, means every checkpoint the tape holds;
///   an empty list means none.
/// * **[goldensAt] says the picture at those steps still looks the same.**
///   Each is compared against `goldenDirectory/<tape>-<step>.png`, recorded on
///   the first local run the way [expectMatchesGolden] records any golden.
///
/// The two answer different questions, which is why one test asks both: a
/// step can be numerically identical and drawn by a renderer that changed,
/// and a step can look the same by eye while the state underneath diverged.
///
/// Everything else is [expectReplayMatches], which does the work.
void testReplay(
  String tapePath, {
  required ReplayStarter start,
  Iterable<int>? digestAt,
  Iterable<int> goldensAt = const <int>[],
  String goldenDirectory = 'test/goldens',
  int width = 320,
  int height = 180,
  double dt = 1.0 / 60.0,
  RenderSettings settings = const RenderSettings(),
  double tolerance = 0.0,
  bool? recordMissing,
  String? description,
  Object? skip,
}) {
  // A level is read through `rootBundle`, which needs the binding up; a game
  // developer should not have to know that to write one line.
  TestWidgetsFlutterBinding.ensureInitialized();
  test(description ?? 'the replay of $tapePath still checks out', () async {
    await expectReplayMatches(
      readTape(tapePath),
      start: start,
      digestAt: digestAt,
      goldensAt: goldensAt,
      goldenDirectory: goldenDirectory,
      goldenName: _stem(tapePath),
      width: width,
      height: height,
      dt: dt,
      settings: settings,
      tolerance: tolerance,
      recordMissing: recordMissing,
      label: tapePath,
    );
  }, skip: skip);
}

/// The tape at [path], or a test failure that says why it could not be read.
///
/// A failure rather than a [DemoFormatException], because it is read in a
/// test report: the path and the reason in one sentence, and what to do.
Demo readTape(String path) {
  final file = File(path);
  if (!file.existsSync()) {
    fail(
      'no tape at $path. A tape is a .f3drun, the JSON of a Demo; record one '
      'by playing the level, or write one with jsonEncode(demo.toJson()).',
    );
  }
  final Object? json;
  try {
    json = jsonDecode(file.readAsStringSync());
  } on FormatException catch (error) {
    fail('$path is not JSON: ${error.message}');
  }
  if (json is! Map<String, Object?>) {
    fail('$path is not a tape: a .f3drun is a JSON object');
  }
  try {
    return Demo.fromJson(json);
  } on DemoFormatException catch (error) {
    fail('$path is not a tape: ${error.message}');
  }
}

/// Replays [demo] into the run [start] builds and checks it at the steps
/// asked for; see [testReplay] for what [digestAt] and [goldensAt] mean.
///
/// [tolerance] and [recordMissing] are [expectMatchesGolden]'s, for every
/// golden of the replay.
///
/// For a game that has its [Demo] in memory rather than in a file — one it
/// has just recorded, say. The golden for step `s` is
/// `goldenDirectory/goldenName-s.png`, and [label] names the tape in every
/// failure.
///
/// **Refuses before it steps** a request it cannot answer: a step past the
/// end of the tape, a digest at a step the tape has no checkpoint for, a
/// test that asks for nothing, and a level that changed since the recording.
/// Each is a mistake in the test or in the tape, and failing on it after a
/// thousand steps of replay would only make the report longer.
Future<void> expectReplayMatches(
  Demo demo, {
  required ReplayStarter start,
  Iterable<int>? digestAt,
  Iterable<int> goldensAt = const <int>[],
  String goldenDirectory = 'test/goldens',
  String goldenName = 'replay',
  int width = 320,
  int height = 180,
  double dt = 1.0 / 60.0,
  RenderSettings settings = const RenderSettings(),
  double tolerance = 0.0,
  bool? recordMissing,
  String label = 'the tape',
}) async {
  final recorded = <int, int>{
    for (final (i, step) in demo.checkpoints.steps.indexed)
      step: demo.checkpoints.digests[i],
  };
  final digests = digestAt?.toSet() ?? recorded.keys.toSet();
  final goldens = goldensAt.toSet();

  final unrecorded = digests.where((step) => !recorded.containsKey(step));
  if (unrecorded.isNotEmpty) {
    fail(
      '$label has no checkpoint at step ${unrecorded.join(', ')}: it took '
      'one every ${demo.checkpoints.every} steps'
      '${recorded.isEmpty ? ' and holds none' : ', ${_some(recorded.keys)}'}. '
      'Ask for one of those, or leave digestAt out to check them all.',
    );
  }
  final outside = goldens.where((step) => step < 1 || step > demo.steps);
  if (outside.isNotEmpty) {
    fail(
      '$label lasts ${demo.steps} steps, so there is no step '
      '${outside.join(', ')} to draw. Ask for a step from 1 to ${demo.steps}, '
      'or record a longer run.',
    );
  }
  if (digests.isEmpty && goldens.isEmpty) {
    fail(
      'this replay of $label checks nothing: '
      '${recorded.isEmpty ? 'the tape holds no checkpoints' : 'digestAt is empty'} '
      'and goldensAt names no step. A replay that checks nothing passes '
      'whatever the game does.',
    );
  }

  final kit = cpuTestDevice(width: width, height: height);
  final renderer = Renderer.create(
    device: kit.device,
    fallbackAlbedo: kit.albedo,
    fallbackNormal: kit.normal,
  );
  final input = InputState();
  final run = await start(
    ReplayStart(demo: demo, input: input, device: kit.device),
  );

  final levelHash = run.levelHash;
  if (levelHash != null && levelHash != demo.levelHash) {
    fail(
      'the level ${demo.level} has changed since $label was recorded: the '
      'tape was played on ${demo.levelHash}, the level is $levelHash now. A '
      'tape played into '
      'edited geometry diverges for a reason that is not a bug; record the '
      'tape again.',
    );
  }

  run.restore(demo.start);
  final playback = InputTapePlayback(demo.tape);
  final last = <int>{...digests, ...goldens}.reduce((a, b) => a > b ? a : b);
  int? agreed;
  for (var step = 1; step <= last; step++) {
    playback.applyTo(input);
    run.step(dt);
    // Before `endStep`, because that is where the recorder took it: the
    // checkpoint is the state the step left, with the step's input still on.
    if (digests.contains(step)) {
      final found = StateDigest.of(run.save().toJson());
      final expected = recorded[step]!;
      if (found != expected) {
        fail(
          '$label diverged at step $step: the tape recorded ${_hex(expected)} '
          'and this build reached ${_hex(found)}. '
          '${agreed == null ? 'No earlier checkpoint was checked' : 'Step $agreed still agreed'}, '
          'so the change is in the steps between. If it is meant, record the '
          'tape again.',
        );
      }
      agreed = step;
    }
    input.endStep();

    if (goldens.contains(step)) {
      final frame = await drawOnce(
        device: kit.device,
        renderer: renderer,
        subject: await run.frame(step),
        width: width,
        height: height,
        settings: settings,
      );
      await expectMatchesGolden(
        frame,
        '$goldenDirectory/$goldenName-$step.png',
        tolerance: tolerance,
        recordMissing: recordMissing,
        reason: 'step $step of $label',
      );
    }
  }
}

String _hex(int digest) => digest.toRadixString(16).padLeft(8, '0');

/// The first few of [steps], for a sentence rather than a column.
String _some(Iterable<int> steps) => steps.length <= 6
    ? 'at ${steps.join(', ')}'
    : 'at ${steps.take(5).join(', ')} and ${steps.length - 5} more';

/// `test/tapes/ascent.f3drun` → `ascent`.
String _stem(String path) {
  final name = path.split(RegExp(r'[/\\]')).last;
  final dot = name.lastIndexOf('.');
  return dot > 0 ? name.substring(0, dot) : name;
}
