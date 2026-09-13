import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter3d_bridge/flutter3d_bridge.dart' show WidgetSurfaceKind;
import 'package:flutter3d_game_shooter/flutter3d_game_shooter.dart' show ShooterActions;
import 'package:flutter3d_game_shooter/sample.dart' show Staged, sampleRegistry, stage;
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:vector_math/vector_math.dart';

import 'sim_renderer.dart';

/// What a tool call actually did, the sentence to say about it, and — for
/// `frame` alone — the PNG that goes with it.
///
/// The same shape `flutter3d_editor_mcp`'s own `Answer` is, widened by one
/// field rather than split into two types: every other tool leaves [png]
/// null, and a caller that only ever reads [says] never has to know the
/// field exists.
typedef Answer = ({bool did, String says, Uint8List? png});

Answer _ok(String says, [Uint8List? png]) =>
    (did: true, says: says, png: png);
Answer _refuse(String says) => (did: false, says: says, png: null);

/// One shooter level, open for the life of the process, an agent can walk
/// through blind.
///
/// **One level at a time, the same discipline `EditorSession` keeps.** A
/// second `open` mid-run would leave the recorded tape and the digest trace
/// describing a level nobody is standing in any more — `open` before a run
/// has anything worth keeping is the only time it is allowed to replace
/// what came before.
final class SimSession {
  Staged? _staged;
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

  bool get isOpen => _staged != null;

  Answer open(String path) {
    final Level level;
    try {
      final json = jsonDecode(File(path).readAsStringSync());
      level = Level.fromJson((json as Map).cast<String, Object?>());
    } catch (error) {
      return _refuse('could not read a level from "$path": $error');
    }
    final world = CollisionWorld();
    level.addTo(world);
    final staged = stage(level, world, input: _input);
    world.update();

    _staged = staged;
    _levelPath = path;
    _levelHash = level.digestHex;
    _recorder = InputTapeRecorder(seed: _seed);
    _digests = DigestTrace(every: _every);
    _step = 0;
    _start = staged.sim.save();
    _renderer = null;

    return _ok('opened "$path" (hash $_levelHash). ${_describe(staged)}');
  }

  /// Steps [steps] fixed steps, holding the same intent for all of them —
  /// [moveX]/[moveY] as a stick, [lookX]/[lookY] added once per step (not
  /// once for the whole call: a look this size held for ten steps is a turn
  /// ten times that size, matching what ten real frames of the same mouse
  /// delta would do), and [fire] held for the whole call when true.
  Answer step({
    required int steps,
    double moveX = 0.0,
    double moveY = 0.0,
    double lookX = 0.0,
    double lookY = 0.0,
    bool fire = false,
  }) {
    final staged = _staged;
    final recorder = _recorder;
    final digests = _digests;
    if (staged == null || recorder == null || digests == null) {
      return _refuse('no level open — call open first');
    }
    if (steps <= 0) {
      return _refuse('steps must be at least 1');
    }

    var wasFiring = _input.pressed(ShooterActions.fire);
    for (var i = 0; i < steps; i++) {
      _input.setStickAxis(moveX, moveY);
      _input.addLook(lookX, lookY);
      if (fire != wasFiring) {
        fire
            ? _input.press(ShooterActions.fire)
            : _input.release(ShooterActions.fire);
        wasFiring = fire;
      }
      recorder.record(_input);
      _input.beginStep();
      staged.sim.step(_dt);
      _step++;
      if (_step % _every == 0) {
        digests.observe(_step, staged.sim.save().toJson());
      }
      _input.endStep();
    }

    return _ok('stepped to $_step. ${_describe(staged)}');
  }

  Answer snapshot() {
    final staged = _staged;
    if (staged == null) return _refuse('no level open');
    return _ok(jsonEncode(_words(staged)));
  }

  Answer digest() {
    final digests = _digests;
    if (digests == null) return _refuse('no level open');
    if (digests.hexDigests.isEmpty) {
      return _ok(
        'no checkpoint yet — every $_every steps gets one, at step $_step now',
      );
    }
    return _ok('step ${digests.steps.last}: ${digests.hexDigests.last}');
  }

  Answer writeRun(String path) {
    final staged = _staged;
    final recorder = _recorder;
    final digests = _digests;
    final start = _start;
    if (staged == null ||
        recorder == null ||
        digests == null ||
        start == null) {
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

  /// A PNG from the player's own eye, looking where they are looking — the
  /// one tool here that needs a device, built lazily on first call and kept
  /// for the rest of the run rather than rebuilt every time.
  Future<Answer> frame() async {
    final staged = _staged;
    final path = _levelPath;
    if (staged == null || path == null) return _refuse('no level open');
    try {
      // `wg-02`'s own kind, added here rather than to `stage`'s own registry
      // (`flutter3d_game_shooter`'s `sample.dart`): a genre package must not
      // gain a dependency on the bridge layer just so its sample registry
      // can speak a word the bridge, not the genre, defines — the same
      // reason `sampleRegistry`'s own `extra` parameter exists.
      final renderer = _renderer ??= await SimRenderer.open(
        path,
        registry: sampleRegistry(extra: const <EntityKind>[WidgetSurfaceKind()]),
      );
      final eye = Vector3.zero();
      final aim = Vector3.zero();
      staged.player
        ..eye(eye)
        ..aim(aim);
      final png = await renderer.frame(at: eye, aim: aim);
      return _ok('a frame from the player\'s own eye, ${png.length} bytes', png);
    } catch (error) {
      return _refuse('could not draw a frame: $error');
    }
  }

  /// A one-line summary — alive, health, where — of the player and every
  /// actor still worth mentioning, for a tool answer that reads as a
  /// sentence rather than as a document.
  String _describe(Staged staged) {
    final player = staged.player;
    final at = player.body.position;
    final health = player.inventory.health;
    final alive = staged.actors.actors.where((a) => a.isAlive).length;
    final total = staged.actors.actors.length;
    return 'player at (${at.x.toStringAsFixed(1)}, ${at.y.toStringAsFixed(1)}, '
        '${at.z.toStringAsFixed(1)}), health ${health.current.toStringAsFixed(0)}'
        '/${health.maximum.toStringAsFixed(0)}, $alive of $total actors still up.';
  }

  /// The full "positions, health, events" reading `snapshot` promises, as
  /// JSON rather than as a sentence — one row per actor, named by
  /// [Actor.name] when the level gave it one and by its index otherwise, so
  /// an agent can tell two monsters of the same kind apart across calls.
  Map<String, Object?> _words(Staged staged) {
    final player = staged.player;
    final at = player.body.position;
    final health = player.inventory.health;
    return <String, Object?>{
      'step': _step,
      'player': <String, Object?>{
        'position': <double>[at.x, at.y, at.z],
        'yaw': player.yaw,
        'health': health.current,
        'maxHealth': health.maximum,
        'alive': player.isAlive,
      },
      'actors': <Map<String, Object?>>[
        for (final actor in staged.actors.actors)
          <String, Object?>{
            'name': actor.name ?? '#${actor.entity.index}',
            'position': actor.position == null
                ? null
                : <double>[
                    actor.position!.x,
                    actor.position!.y,
                    actor.position!.z,
                  ],
            'health': actor.health?.current,
            'alive': actor.isAlive,
          },
      ],
    };
  }
}
