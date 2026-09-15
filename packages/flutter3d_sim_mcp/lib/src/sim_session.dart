import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter3d_mcp_kit/flutter3d_mcp_kit.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:vector_math/vector_math.dart';

import 'diagnostic_session.dart';
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

  /// `par-02`'s own session, open beside this one rather than instead of
  /// it: playing a level blind and diagnosing a rendered frame are two
  /// different questions, one genre-shaped and one not, and folding
  /// `DiagnosticSession`'s state into this class would give this one's
  /// `open` an opinion about the other's level. What they share now is a
  /// process and a tool table — `flutter3d_render_mcp`'s own former one,
  /// before it merged into this package.
  final DiagnosticSession diagnostic = DiagnosticSession();

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
    final recorder = _recorder;
    final digests = _digests;
    if (run == null || recorder == null || digests == null) {
      return _refuse('no level open — call open first');
    }
    if (steps <= 0) {
      return _refuse('steps must be at least 1');
    }
    for (final String name in held.keys) {
      if (!game.buttons.containsKey(name)) {
        return _refuse(
          'the ${game.name} has no button called "$name"; it has '
          '${game.buttons.keys.join(', ')}',
        );
      }
    }

    // A button changes at most once a call, before the first step reads it.
    for (final MapEntry<String, GameAction> button in game.buttons.entries) {
      final bool down = held[button.key] ?? false;
      if (down == _input.pressed(button.value)) continue;
      down ? _input.press(button.value) : _input.release(button.value);
    }
    for (var i = 0; i < steps; i++) {
      _input.setStickAxis(moveX, moveY);
      _input.addLook(lookX, lookY);
      recorder.record(_input);
      _input.beginStep();
      run.step(_dt);
      _step++;
      if (_step % _every == 0) {
        digests.observe(_step, run.save().toJson());
      }
      _input.endStep();
    }

    return _ok('stepped to $_step. ${run.summary}');
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
    final run = _run;
    final recorder = _recorder;
    final digests = _digests;
    final start = _start;
    if (run == null || recorder == null || digests == null || start == null) {
      return _refuse('no level open — nothing recorded to write');
    }
    final demo = Demo(
      level: _levelPath!,
      levelHash: _levelHash!,
      start: start,
      tape: recorder.tape,
      buildStamp: 'flutter3d_sim_mcp',
      checkpoints: digests,
    );
    try {
      File(path).writeAsStringSync(jsonEncode(demo.toJson()));
    } catch (error) {
      return _refuse('could not write "$path": $error');
    }
    return _ok(
      'wrote $path — ${recorder.tape.steps} steps, ${digests.steps.length} checkpoints',
    );
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
