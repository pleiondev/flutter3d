import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter3d_mcp/kit.dart';
import 'package:flutter3d_physics/flutter3d_physics.dart';
import 'package:flutter3d_physics_native/flutter3d_physics_native.dart'
    show choosePhysics, usePhysics;
import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart';
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
  SimSession({required this.game, this.entities, ProjectRoot? root})
    : root = root ?? ProjectRoot.around(null);

  /// The directory every path this session is handed must lie inside: the
  /// level [open] reads, the runs [verify] and [bisect] read and the level
  /// each of them names, and the `.f3drun` [writeRun] and [expect] write.
  /// The working directory when not given.
  final ProjectRoot root;

  /// What this session plays — `flutter3d_game_shooter`'s
  /// `ShooterHeadlessGame`, for the crypt.
  final HeadlessGame game;

  /// Where [game]'s saves keep their entities, so [bisect] can name the
  /// entity and the component two runs part on rather than only a path into
  /// the raw save; null when the host did not say, and a `bisect` call may
  /// say instead.
  ///
  /// **The host's to give, not the game's to answer.** [HeadlessGame] is an
  /// interface every genre implements, and a save is whatever that genre's
  /// `save()` writes; the composition that hands this server a game is the
  /// one place that knows both.
  final EntityLayout? entities;

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
      final json = jsonDecode(_readInside(path));
      level = Level.fromJson((json as Map).cast<String, Object?>());
    } catch (error) {
      return _refuse('could not read a level from "$path": $error');
    }
    // The session's physics, chosen the first time it is asked.
    final world = CollisionWorld(backend: usePhysics());
    level.addTo(world);
    world.backend.attach(world);
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

  /// Gives the order [verb] with [arguments], then steps [steps] fixed steps
  /// with the stick at rest — for a [game] that is an [OrderedGame].
  ///
  /// **The order goes through the input**, as [OrderTunes] writes it, so it
  /// is on the tape with the first of those steps: [writeRun] keeps it,
  /// [verify] and [bisect] give it again at the same step. The buttons stay
  /// as the last [step] left them.
  ///
  /// Refused for a game that takes no orders, for a verb it does not know,
  /// and for an argument the verb does not read or that is not a number.
  PictureAnswer order({
    required String verb,
    Map<String, Object?> arguments = const <String, Object?>{},
    int steps = 1,
  }) {
    final run = _run;
    if (run == null) return _refuse('no level open — call open first');
    final game = this.game;
    if (game is! OrderedGame) {
      return _refuse('the ${game.name} takes no orders; step it instead');
    }
    final known = game.orders[verb];
    if (known == null) {
      return _refuse(
        'the ${game.name} has no order "$verb"; it has '
        '${game.orders.keys.join(', ')}',
      );
    }
    if (steps <= 0) return _refuse('steps must be at least 1');
    final numbers = <String, double>{};
    for (final MapEntry(:key, :value) in arguments.entries) {
      if (!known.arguments.containsKey(key)) {
        return _refuse(
          '"$verb" reads no "$key"; it reads '
          '${known.arguments.isEmpty ? 'nothing' : known.arguments.keys.join(', ')}',
        );
      }
      if (value is! num) return _refuse('"$key" is a number');
      numbers[key] = value.toDouble();
    }
    OrderTunes.give(_input, verb, numbers);
    for (var i = 0; i < steps; i++) {
      _advance(run, 0.0, 0.0, 0.0, 0.0);
    }
    return _ok('gave "$verb", stepped to $_step. ${run.summary}');
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

  /// Two runs of one level played side by side, each in a world of its own,
  /// to the first step at which they differ — and what differs there, as
  /// a path into the state: `actors.3.health`.
  ///
  /// **Every step, not every checkpoint.** A run's checkpoints bracket a
  /// defect to tens of steps; two tapes in hand can be stepped together and
  /// compared at each, which names the step the two first part on. Two runs
  /// on other physics, or in other versions of the level, would part at the
  /// first step for a reason nobody needs told, so both are refused.
  ///
  /// With [layout], or the session's [entities] when it is left out, the
  /// answer also names every entity component that differs at that step,
  /// the first of them where the path starts: `7.vitality.hp`. A step where
  /// the runs part outside the entities — in the player, in the random
  /// state — says that no component differs there, which is news too.
  PictureAnswer bisect(String pathA, String pathB, {EntityLayout? layout}) {
    final entityLayout = layout ?? entities;
    final runs = <Demo>[];
    for (final path in <String>[pathA, pathB]) {
      try {
        final json = jsonDecode(_readInside(path));
        runs.add(Demo.fromJson((json as Map).cast<String, Object?>()));
      } on DemoFormatException catch (error) {
        return _refuse('"$path" is not a run: ${error.message}');
      } catch (error) {
        return _refuse('could not read a run from "$path": $error');
      }
    }
    final [a, b] = runs;
    if (a.levelHash != b.levelHash) {
      return _refuse(
        'the two were played in different levels, or different versions of '
        'one (${a.levelHash} and ${b.levelHash})',
      );
    }
    if (a.physics != b.physics) {
      return _refuse(
        'the two were played on different physics (${a.physics} and '
        '${b.physics}), which are not promised to agree',
      );
    }
    if (a.levelSwaps.isNotEmpty || b.levelSwaps.isNotEmpty) {
      return _refuse('a run with its level edited under it is not bisected');
    }
    final Level level;
    try {
      final json = jsonDecode(_readInside(a.level));
      level = Level.fromJson((json as Map).cast<String, Object?>());
    } catch (error) {
      return _refuse('could not read the runs\' level "${a.level}": $error');
    }
    if (level.digestHex != a.levelHash) {
      return _refuse(
        'the level at "${a.level}" has changed since the runs were recorded',
      );
    }
    return _onPhysicsOf(a, () {
      // Each side a run of its own in a loop of its own: the loop's captures
      // hold the run's save as a part, so the rewinds and the comparisons go
      // the loop's one way, and the layout reads the save inside them.
      ReplaySide? side(Demo demo) {
        final world = CollisionWorld(backend: usePhysics());
        level.addTo(world);
        world.backend.attach(world);
        final input = InputState();
        final run = game.start(level, world, input);
        world.update();
        // The standard rate, sixty a second: the loop hands the run 1 / 60,
        // which is [_dt], the step the runs were recorded at.
        final stepped = RunLoop(run, input: input);
        if (!stepped.isRestorable) return null;
        return ReplaySide.loop(
          stepped.loop,
          tape: demo.tape,
          start: stepped.captureFrom(demo.start),
        );
      }

      final (one, two) = (side(a), side(b));
      if (one == null || two == null) {
        return _refuse(
          'a ${game.name} run cannot be put back to a state it saved, which '
          'bisecting two runs needs',
        );
      }
      final inLoop = entityLayout?.under(RunLoop.savePath);
      return switch (bisectTapes(a: one, b: two, layout: inLoop)) {
        TapesAgree() && final agree => (did: true, says: '$agree', png: null),
        final TapesDiverge parted => (
          did: true,
          says:
              'the runs agree for ${parted.step - 1} steps and part at step '
              '${parted.step}: $parted'
              '${entityLayout == null ? '' : _components(parted)}',
          png: null,
        ),
      };
    });
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
      final json = jsonDecode(_readInside(path));
      demo = Demo.fromJson((json as Map).cast<String, Object?>());
    } on DemoFormatException catch (error) {
      return _refuse('"$path" is not a run: ${error.message}');
    } catch (error) {
      return _refuse('could not read a run from "$path": $error');
    }
    // A tape of intents means something only in the simulation that recorded
    // it (decision 9): refused before playing, with both numbers named, when
    // the game can say which one it is. What still plays is the pose record.
    if (game.simulation case final SimulationVersion simulation) {
      if (demo.refusalOn(simulation) case final String reason) {
        return _refuse(
          '"$path" is not replayed: $reason'
          '${demo.poses == null ? '' : ' — its pose record still shows the run'}',
        );
      }
    }
    // A swapped level goes in through the game's own build, which a session
    // over a bare simulation does not have; playing through the swap would
    // answer with a divergence the simulation did not cause.
    if (demo.levelSwaps case [final first, ...]) {
      return _refuse(
        '"$path" has the level edited under it at step ${first.step}, and '
        'this replays a run in one level — play it in the game it was '
        'recorded in',
      );
    }
    final ReadingPredicate? claim;
    try {
      claim = predicate == null ? null : ReadingPredicate.fromJson(predicate);
    } on ReadingPredicateException catch (error) {
      return _refuse(error.message);
    }
    final Level level;
    try {
      final json = jsonDecode(_readInside(demo.level));
      level = Level.fromJson((json as Map).cast<String, Object?>());
    } catch (error) {
      return _refuse('could not read the run\'s level "${demo.level}": $error');
    }
    // The same replay N7's telemetry server reads metrics off, so a run this
    // tool calls verified is a run that server would take.
    final ResimulationRetraced retraced;
    switch (_onPhysicsOf(
      demo,
      // The backend `_onPhysicsOf` just chose, handed in: `resimulate`'s
      // own default is the Dart one, which refuses a native run.
      () => resimulate(
        game: game,
        level: level,
        demo: demo,
        dt: _dt,
        physics: usePhysics(),
      ),
    )) {
      case ResimulationLevelChanged(:final found, :final recorded):
        return _refuse(
          'the level at "${demo.level}" has changed since the run was '
          'recorded (hash $found, the run says $recorded) — a tape played '
          'into different geometry proves nothing',
        );
      case ResimulationOnOtherPhysics(:final recorded, :final running):
        return _refuse(
          '"$path" was recorded on the $recorded physics and this session '
          'runs $running, which is not promised to agree with it',
        );
      // A run that does not start where the recording started diverges
      // before its first step, and saying so is more use than the
      // checkpoint after.
      case ResimulationStartDiffers():
        return _refuse(
          'diverges before the first step: a fresh ${game.name} run of '
          '"${demo.level}" does not start where "$path" started',
        );
      case final ResimulationDiverged diverged:
        return _refuse(
          'diverges — ${diverged.divergence}; the difference arose after '
          'step ${diverged.agreedUntil}',
        );
      case final ResimulationRetraced found:
        retraced = found;
    }
    final run = retraced.run;
    final hex = retraced.finalDigest.toRadixString(16).padLeft(8, '0');
    final agrees =
        'replayed ${demo.steps} steps of "$path": agrees at all '
        '${retraced.checkpoints} checkpoints, ends at step ${demo.steps}, '
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

  /// The text of the file at [path], refused by [root] before it is opened
  /// when it lies outside: a parse error would quote what it read.
  String _readInside(String path) =>
      File(root.resolve(path)).readAsStringSync();

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
      physics: usePhysics().name,
      simulation: game.simulation,
    );
    try {
      File(root.resolve(path)).writeAsStringSync(jsonEncode(demo.toJson()));
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
        root.resolve(path),
        registry: game.registry(),
        root: root,
      );
      // The eye in the world, in doubles: the renderer narrows it through
      // its scene's own origin, which it keeps near the eye.
      final aim = Vector3.zero();
      run.aim(aim);
      final png = await renderer.frameFrom(eye: run.eye, aim: aim);
      return _ok(
        'a frame from the player\'s own eye, ${png.length} bytes',
        png,
      );
    } catch (error) {
      return _refuse('could not draw a frame: $error');
    }
  }
}

/// The sentence a bisection read through an [EntityLayout] ends with: the
/// first component that differs and every other one, or that none does.
String _components(TapesDiverge parted) => switch (parted.components) {
  [] => '. No entity component differs at that step',
  [final first] => '. The component that differs is $first',
  [final first, ...final rest] =>
    '. The first component that differs is $first; also '
        '${rest.take(12).join(', ')}'
        '${rest.length > 12 ? ' and ${rest.length - 12} more' : ''}',
};

/// [body] on the physics [demo] was recorded on, and the session's own
/// again after: the two backends are not promised to agree, so a run is
/// verified on its own. Where that one cannot be had, `resimulate` says so.
T _onPhysicsOf<T>(Demo demo, T Function() body) {
  final was = usePhysics().name;
  final wanted = demo.physics ?? was;
  if (wanted == was) return body();
  choosePhysics(wanted);
  try {
    return body();
  } finally {
    choosePhysics(was);
  }
}
