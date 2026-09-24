import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter3d_mcp_kit/flutter3d_mcp_kit.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:vector_math/vector_math.dart';

import 'reading_predicate.dart';
import 'sim_renderer.dart';

PictureAnswer _ok(String says, [Uint8List? png]) =>
    (did: true, says: says, png: png);
PictureAnswer _refuse(String says) => (did: false, says: says, png: null);

/// One level of [game], open for the life of the process, an agent can walk
/// through blind.
///
/// **The game is handed in, not imported.** This server used to import the
/// shooter and call its player, its inventory and its fire button directly,
/// and kept a copy of the dungeon's own assembly to do it — so it could play
/// one genre, and a second would have been a second server. What it needs of a
/// game is what `flutter3d_sim`'s [HeadlessGame] says: start a run, step it,
/// read it back, and the buttons an agent may hold. A host composes the rest.
///
/// **One level at a time, the same discipline `EditorSession` keeps.** A
/// second `open` mid-run would leave the recorded tape and the digest trace
/// describing a level nobody is standing in any more — `open` before a run
/// has anything worth keeping is the only time it is allowed to replace
/// what came before.
final class SimSession {
  SimSession({required this.game});

  /// What this session plays — `flutter3d_game_shooter`'s
  /// `ShooterHeadlessGame`, for the crypt.
  final HeadlessGame game;

  HeadlessRun? _run;
  InputTapeRecorder? _recorder;
  DigestTrace? _digests;
  String? _levelPath;
  String? _levelHash;
  int _step = 0;
  Snapshot? _start;
  SimRenderer? _renderer;
  final InputState _input = InputState();

  static const int _seed = 1;
  static const double _dt = 1.0 / 60.0;
  static const int _every = 25;

  bool get isOpen => _run != null;

  PictureAnswer open(String path) {
    final Level level;
    try {
      final json = jsonDecode(File(path).readAsStringSync());
      level = Level.fromJson((json as Map).cast<String, Object?>());
    } catch (error) {
      return _refuse('could not read a level from "$path": $error');
    }
    final world = CollisionWorld();
    level.addTo(world);
    final run = game.start(level, world, _input);
    world.update();

    _run = run;
    _levelPath = path;
    _levelHash = level.digestHex;
    _recorder = InputTapeRecorder(seed: _seed);
    _digests = DigestTrace(every: _every);
    _step = 0;
    _start = run.save();
    _renderer = null;

    return _ok('opened "$path" (hash $_levelHash). ${run.summary}');
  }

  /// Steps [steps] fixed steps, holding the same intent for all of them —
  /// [moveX]/[moveY] as a stick, [lookX]/[lookY] added once per step (not
  /// once for the whole call: a look this size held for ten steps is a turn
  /// ten times that size, matching what ten real frames of the same mouse
  /// delta would do), and every one of [game]'s buttons down for the whole
  /// call when [held] names it true and up otherwise.
  PictureAnswer step({
    required int steps,
    double moveX = 0.0,
    double moveY = 0.0,
    double lookX = 0.0,
    double lookY = 0.0,
    Map<String, bool> held = const <String, bool>{},
  }) {
    final run = _run;
    if (run == null) return _refuse('no level open — call open first');
    if (steps <= 0) {
      return _refuse('steps must be at least 1');
    }
    final unknown = _unknownButton(held);
    if (unknown != null) return _refuse(unknown);

    _hold(held);
    for (var i = 0; i < steps; i++) {
      _advance(run, moveX, moveY, lookX, lookY);
    }

    return _ok('stepped to $_step. ${run.summary}');
  }

  /// Steps with one intent held — the same arguments as [step] — until
  /// [predicate] holds over [HeadlessRun.reading] or [limit] steps have
  /// passed, then writes the whole run so far to [path] as a `.f3drun`.
  ///
  /// **The answer is the evidence, not only the verdict.** It names the step
  /// the claim held at and the digest of the state there, and the file is the
  /// tape that got there: [verify] on it replays to the same step and the
  /// same digest, on any machine, with nobody taking the agent's word for it.
  /// A claim that did not hold is written too, because the run that failed to
  /// reach somewhere is exactly the one worth replaying.
  ///
  /// Checked before the first step as well as after each one: a claim that
  /// already holds is answered at the step it holds at, with nothing stepped.
  PictureAnswer expect({
    required Map<String, Object?> predicate,
    required int limit,
    required String path,
    double moveX = 0.0,
    double moveY = 0.0,
    double lookX = 0.0,
    double lookY = 0.0,
    Map<String, bool> held = const <String, bool>{},
  }) {
    final run = _run;
    if (run == null) return _refuse('no level open — call open first');
    if (limit <= 0) return _refuse('limit must be at least 1');
    final unknown = _unknownButton(held);
    if (unknown != null) return _refuse(unknown);
    final ReadingPredicate claim;
    final bool already;
    try {
      claim = ReadingPredicate.fromJson(predicate);
      // Asked once before anything moves, so a claim about nobody is refused
      // with the level still where it was.
      already = claim.holds(run.reading);
    } on ReadingPredicateException catch (error) {
      return _refuse(error.message);
    }

    final from = _step;
    if (!already) _hold(held);
    // The step counter is the loop's own state; the claim is asked once a
    // step, after the step has run.
    var holds = already;
    // A game that removes what it kills can take the claim's subject out of
    // the reading mid-run; that ends the run as a claim about nobody, with
    // the tape that got there still written.
    String? lost;
    while (!holds && lost == null && _step - from < limit) {
      _advance(run, moveX, moveY, lookX, lookY);
      try {
        holds = claim.holds(run.reading);
      } on ReadingPredicateException catch (error) {
        lost = error.message;
      }
    }

    final digest = StateDigest.of(run.save().toJson());
    final hex = digest.toRadixString(16).padLeft(8, '0');
    final failed = _writeDemo(path);
    final evidence = failed ?? 'wrote $path';
    // A claim that held but left no file behind is only the agent's word.
    if (lost != null || failed != null) {
      return _refuse(
        '${claim.describe()}: ${holds ? 'held' : 'stopped'} at step $_step, '
        'digest $hex${lost == null ? '' : ' — $lost'}. $evidence. '
        '${run.summary}',
      );
    }
    return holds
        ? _ok(
            '${claim.describe()}: holds at step $_step, digest $hex, '
            '${_step - from} steps in. $evidence. ${run.summary}',
          )
        : _refuse(
            '${claim.describe()}: did not hold within $limit steps; at step '
            '$_step, digest $hex. $evidence. ${run.summary}',
          );
  }

  /// Replays the `.f3drun` at [path] into a fresh run of its own level and
  /// answers whether it retraces the checkpoints it was written with — and,
  /// when [predicate] is given, whether that claim holds where the replay
  /// ends.
  ///
  /// **A world of its own**, beside whatever run this session has open, which
  /// it neither reads nor moves: a replay checked inside the agent's own run
  /// would be checking the agent against itself.
  ///
  /// A disagreement is answered with [DigestTrace.divergenceFrom]'s step,
  /// which brackets the defect to the checkpoints either side of it.
  PictureAnswer verify(String path, {Map<String, Object?>? predicate}) {
    final Demo demo;
    try {
      final json = jsonDecode(File(path).readAsStringSync());
      demo = Demo.fromJson((json as Map).cast<String, Object?>());
    } on DemoFormatException catch (error) {
      return _refuse('"$path" is not a run: ${error.message}');
    } catch (error) {
      return _refuse('could not read a run from "$path": $error');
    }
    final ReadingPredicate? claim;
    try {
      claim = predicate == null ? null : ReadingPredicate.fromJson(predicate);
    } on ReadingPredicateException catch (error) {
      return _refuse(error.message);
    }
    final Level level;
    try {
      final json = jsonDecode(File(demo.level).readAsStringSync());
      level = Level.fromJson((json as Map).cast<String, Object?>());
    } catch (error) {
      return _refuse('could not read the run\'s level "${demo.level}": $error');
    }
    if (level.digestHex != demo.levelHash) {
      return _refuse(
        'the level at "${demo.level}" has changed since the run was recorded '
        '(hash ${level.digestHex}, the run says ${demo.levelHash}) — a tape '
        'played into different geometry proves nothing',
      );
    }

    final world = CollisionWorld();
    level.addTo(world);
    final input = InputState();
    final run = game.start(level, world, input);
    world.update();
    // A run that does not start where the recording started diverges before
    // its first step, and saying so is more use than the checkpoint after.
    if (StateDigest.of(run.save().toJson()) !=
        StateDigest.of(demo.start.toJson())) {
      return _refuse(
        'diverges before the first step: a fresh ${game.name} run of '
        '"${demo.level}" does not start where "$path" started',
      );
    }

    final playback = InputTapePlayback(demo.tape);
    final trace = DigestTrace(every: demo.checkpoints.every);
    for (var step = 1; step <= demo.steps; step++) {
      playback.applyTo(input);
      input.beginStep();
      run.step(_dt);
      if (step % trace.every == 0) trace.observe(step, run.save().toJson());
      input.endStep();
    }

    final divergence = trace.divergenceFrom(demo.checkpoints.digests);
    if (divergence != null) {
      return _refuse(
        'diverges — $divergence; the difference arose after step '
        '${math.max(0, divergence.step - trace.every)}',
      );
    }
    final hex = StateDigest.of(
      run.save().toJson(),
    ).toRadixString(16).padLeft(8, '0');
    final agrees =
        'replayed ${demo.steps} steps of "$path": agrees at all '
        '${trace.steps.length} checkpoints, ends at step ${demo.steps}, '
        'digest $hex';
    if (claim == null) return _ok('$agrees. ${run.summary}');
    try {
      return claim.holds(run.reading)
          ? _ok('$agrees; ${claim.describe()} holds there. ${run.summary}')
          : _refuse(
              '$agrees; but ${claim.describe()} does not hold there. '
              '${run.summary}',
            );
    } on ReadingPredicateException catch (error) {
      return _refuse('$agrees; but ${error.message}');
    }
  }

  /// A sentence naming the first of [held] that [game] has no button for, or
  /// null when it has all of them.
  String? _unknownButton(Map<String, bool> held) {
    for (final String name in held.keys) {
      if (!game.buttons.containsKey(name)) {
        return 'the ${game.name} has no button called "$name"; it has '
            '${game.buttons.keys.join(', ')}';
      }
    }
    return null;
  }

  /// Puts every one of [game]'s buttons down or up as [held] says. A button
  /// changes at most once a call, before the first step reads it.
  void _hold(Map<String, bool> held) {
    for (final MapEntry<String, GameAction> button in game.buttons.entries) {
      final bool down = held[button.key] ?? false;
      if (down == _input.pressed(button.value)) continue;
      down ? _input.press(button.value) : _input.release(button.value);
    }
  }

  /// One fixed step of [run] with the stick and look given, recorded on the
  /// tape and checkpointed on the trace.
  void _advance(
    HeadlessRun run,
    double moveX,
    double moveY,
    double lookX,
    double lookY,
  ) {
    _input.setStickAxis(moveX, moveY);
    _input.addLook(lookX, lookY);
    _recorder!.record(_input);
    _input.beginStep();
    run.step(_dt);
    _step++;
    if (_step % _every == 0) {
      _digests!.observe(_step, run.save().toJson());
    }
    _input.endStep();
  }

  /// How things stand as data: the step, then whatever the game reads out.
  PictureAnswer snapshot() {
    final run = _run;
    if (run == null) return _refuse('no level open');
    return _ok(jsonEncode(<String, Object?>{'step': _step, ...run.reading}));
  }

  PictureAnswer digest() {
    final digests = _digests;
    if (digests == null) return _refuse('no level open');
    if (digests.hexDigests.isEmpty) {
      return _ok(
        'no checkpoint yet — every $_every steps gets one, at step $_step now',
      );
    }
    return _ok('step ${digests.steps.last}: ${digests.hexDigests.last}');
  }

  PictureAnswer writeRun(String path) {
    final recorder = _recorder;
    final digests = _digests;
    if (_run == null || recorder == null || digests == null) {
      return _refuse('no level open — nothing recorded to write');
    }
    final failed = _writeDemo(path);
    if (failed != null) return _refuse(failed);
    return _ok(
      'wrote $path — ${recorder.tape.steps} steps, ${digests.steps.length} checkpoints',
    );
  }

  /// Writes the run so far to [path], or says why it could not.
  String? _writeDemo(String path) {
    final demo = Demo(
      level: _levelPath!,
      levelHash: _levelHash!,
      start: _start!,
      tape: _recorder!.tape,
      buildStamp: 'flutter3d_sim_mcp',
      checkpoints: _digests!,
    );
    try {
      File(path).writeAsStringSync(jsonEncode(demo.toJson()));
    } catch (error) {
      return 'could not write "$path": $error';
    }
    return null;
  }

  /// A PNG from the eye of whoever the input moves, looking where they look —
  /// the one tool here that needs a device, built lazily on first call and
  /// kept for the rest of the run rather than rebuilt every time.
  Future<PictureAnswer> frame() async {
    final run = _run;
    final path = _levelPath;
    if (run == null || path == null) return _refuse('no level open');
    try {
      final renderer = _renderer ??= await SimRenderer.open(
        path,
        registry: game.registry(),
      );
      final eye = Vector3.zero();
      final aim = Vector3.zero();
      run
        ..eye(eye)
        ..aim(aim);
      final png = await renderer.frame(at: eye, aim: aim);
      return _ok(
        'a frame from the player\'s own eye, ${png.length} bytes',
        png,
      );
    } catch (error) {
      return _refuse('could not draw a frame: $error');
    }
  }
}
