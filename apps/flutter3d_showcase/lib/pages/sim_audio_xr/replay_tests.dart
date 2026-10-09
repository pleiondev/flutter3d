/// A recorded run as a test: the tape played back into the game with no
/// screen, and the digest of its state checked against the recording at the
/// steps it was taken, so a change to the simulation fails the build at the
/// step it first shows.
///
/// **`testReplay` itself is not called here.** It lives in
/// `flutter3d_testing`, registers a `flutter_test` test and reads the tape
/// from a file, none of which a page in a running app can do. Its loop is a
/// dozen lines over `flutter3d_sim` types — `Demo`, `InputTapePlayback`,
/// `StateDigest` — and this page carries that loop over, with the same
/// refusals and the same sentence on a divergence.
///
/// Quoted by `replay_tests.md` and shown whole in the Source tab.
library;

import 'dart:convert';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_showcase/src/demo/demo.dart';
import 'package:flutter3d_showcase/src/demo/scene_kit.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';

// #region game
/// A ball pushed along a track between two walls. [restitution] is how
/// hard it bounces off them, the number the planted change touches: a run
/// that never reaches a wall cannot tell two builds apart.
final class _Ball {
  _Ball({this.restitution = 0.8, this.wall = 6.0});

  final double restitution;
  final double wall;
  double x = 0.0;
  double v = 0.0;
  int bounces = 0;

  /// What a tape is checked against before it is played: the level, so an
  /// edited level is refused instead of reported as a bug.
  String get levelHash => contentDigestHex(<String, Object?>{'wall': wall});

  void restore(Snapshot start) {
    x = start.data.number('x');
    v = start.data.number('v');
    bounces = start.data.integer('bounces');
  }

  void step(InputState input) {
    v = (v + input.moveAxis.x * 0.002) * 0.995;
    x += v;
    if (x > wall || x < 0.0) {
      x = x > wall ? 2.0 * wall - x : -x;
      v = -v * restitution;
      bounces++;
    }
  }

  Snapshot save() =>
      Snapshot(<String, Object?>{'x': x, 'v': v, 'bounces': bounces});
}
// #endregion game

// #region record
/// What a recording session leaves behind: the start, the tape, and a
/// digest every twenty steps, written out as a `.f3drun` would be and read
/// back the way a test reads one.
Demo _record() {
  final _Ball game = _Ball();
  final Snapshot start = game.save();
  final InputTape tape = InputTape(
    seed: 0,
    frames: <InputFrame>[
      for (var i = 0; i < 240; i++)
        InputFrame(stickX: i < 120 ? 1.0 : (i < 170 ? 0.0 : -1.0)),
    ],
  );
  final DigestTrace checkpoints = DigestTrace(every: 20);
  final InputState input = InputState();
  final InputTapePlayback playback = InputTapePlayback(tape);
  for (var step = 1; step <= tape.steps; step++) {
    playback.applyTo(input);
    game.step(input);
    checkpoints.observe(step, game.save().toJson());
    input.endStep();
  }
  final Demo demo = Demo(
    level: 'track',
    levelHash: game.levelHash,
    start: start,
    tape: tape,
    buildStamp: 'showcase',
    checkpoints: checkpoints,
  );
  return Demo.fromJson(
    jsonDecode(jsonEncode(demo.toJson())) as Map<String, Object?>,
  );
}
// #endregion record

/// What a replay of a tape came to.
sealed class _Verdict {
  const _Verdict();
}

/// Every checkpoint asked for agreed.
final class _Agreed extends _Verdict {
  const _Agreed(this.steps);
  final List<int> steps;

  @override
  String toString() => 'agreed at steps ${steps.join(', ')}';
}

/// The first checkpoint that did not, and the last one that did.
final class _Diverged extends _Verdict {
  const _Diverged(this.step, this.agreed, this.expected, this.found);
  final int step;
  final int? agreed;
  final int expected;
  final int found;

  @override
  String toString() =>
      'diverged at step $step: the tape recorded ${_hex(expected)} and this '
      'build reached ${_hex(found)}; '
      '${agreed == null ? 'no earlier checkpoint was checked' : 'step $agreed still agreed'}';
}

/// Nothing was played, and why.
final class _Refused extends _Verdict {
  const _Refused(this.reason);
  final String reason;

  @override
  String toString() => reason;
}

String _hex(int digest) => digest.toRadixString(16).padLeft(8, '0');

// #region replay
/// [demo] played into [game] with no screen, its digest checked at each
/// step of [digestAt] — every checkpoint the tape holds when left out.
_Verdict _replay(Demo demo, _Ball game, {Iterable<int>? digestAt}) {
  final Map<int, int> recorded = <int, int>{
    for (final (int i, int step) in demo.checkpoints.steps.indexed)
      step: demo.checkpoints.digests[i],
  };
  final Set<int> digests = digestAt?.toSet() ?? recorded.keys.toSet();

  // Refused before the first step, each with what to do instead.
  final Iterable<int> missing = digests.where((s) => !recorded.containsKey(s));
  if (missing.isNotEmpty) {
    return _Refused(
      'the tape has no checkpoint at step ${missing.join(', ')}: it took one '
      'every ${demo.checkpoints.every} steps',
    );
  }
  if (digests.isEmpty) {
    return const _Refused(
      'this replay checks nothing, so it would pass whatever the game does',
    );
  }
  if (game.levelHash != demo.levelHash) {
    return _Refused(
      'the level has changed since the tape was recorded: it was played on '
      '${demo.levelHash}, the level is ${game.levelHash} now',
    );
  }

  game.restore(demo.start);
  final InputState input = InputState();
  final InputTapePlayback playback = InputTapePlayback(demo.tape);
  final int last = digests.reduce((a, b) => a > b ? a : b);
  int? agreed;
  for (var step = 1; step <= last; step++) {
    playback.applyTo(input);
    game.step(input);
    if (digests.contains(step)) {
      final int found = StateDigest.of(game.save().toJson());
      if (found != recorded[step]) {
        return _Diverged(step, agreed, recorded[step]!, found);
      }
      agreed = step;
    }
    input.endStep();
  }
  return _Agreed(digests.toList()..sort());
}
// #endregion replay

final class ReplayTestsDemo extends ShowcaseDemo {
  late final Demo _tape;

  /// Whether the lower lane runs the build with the planted change.
  bool planted = true;
  bool _dirty = true;
  late _Verdict _lower;

  final _Ball _upperBall = _Ball();
  late _Ball _lowerBall;
  final InputState _upperInput = InputState();
  final InputState _lowerInput = InputState();
  late InputTapePlayback _upperPlay;
  late InputTapePlayback _lowerPlay;

  late final MeshNode _upper;
  late final MeshNode _lowerNode;
  late final List<MeshNode> _lamps;

  static const double _restitution = 0.8;

  /// The planted change: a bounce a hair softer. Nothing differs until the
  /// ball first reaches a wall.
  static const double _changed = 0.79;

  @override
  void configureView(DemoContext context) {
    context.orbit
      ..distance = 9.0
      ..pitch = 0.6
      ..yaw = 0.0;
    context.orbit.target.setValues(0.0, 0.3, 0.0);
  }

  @override
  Scene build(DemoContext context) {
    _tape = _record();
    _upper = ballNode(context, 'this build', 0.25, Vector4(0.4, 0.7, 0.95, 1));
    _lowerNode = ballNode(
      context,
      'the other build',
      0.25,
      Vector4(0.95, 0.65, 0.3, 1),
    );
    _lamps = <MeshNode>[
      for (final (int k, int step) in _tape.checkpoints.steps.indexed)
        ballNode(
          context,
          'checkpoint $step',
          0.14,
          Vector4(0.3, 0.3, 0.33, 1),
          at: Vector3(-3.0 + k * 6.0 / 11.0, 0.15, 2.0),
        ),
    ];
    _restart();
    return sceneOf(<SceneNode>[
      floorNode(context, width: 8.0, depth: 5.0),
      for (final double z in <double>[-0.6, 0.6])
        for (final double x in <double>[-3.15, 3.15])
          blockNode(
            context,
            'wall',
            Vector3(0.1, 0.6, 0.8),
            Vector4(0.6, 0.6, 0.62, 1),
            at: Vector3(x, 0.3, z),
          ),
      _upper,
      _lowerNode,
      ..._lamps,
    ]);
  }

  void _restart() {
    _lowerBall = _Ball(restitution: planted ? _changed : _restitution);
    _lower = _replay(_tape, _lowerBall);
    _upperBall.restore(_tape.start);
    _lowerBall.restore(_tape.start);
    _upperPlay = InputTapePlayback(_tape.tape);
    _lowerPlay = InputTapePlayback(_tape.tape);
    // The lamps are the lower lane's checkpoints: green while they agree,
    // red where the replay failed, dark after it, since a failed replay stops.
    for (final (int k, int step) in _tape.checkpoints.steps.indexed) {
      final Vector4 color = switch (_lower) {
        _Diverged(step: final at) when step == at => Vector4(0.9, 0.3, 0.3, 1),
        _Diverged(step: final at) when step > at => Vector4(0.3, 0.3, 0.33, 1),
        _ => Vector4(0.35, 0.85, 0.4, 1),
      };
      _lamps[k].material.baseColor = _fromSrgb(color);
    }
  }

  @override
  void update(DemoContext context, double dt) {
    if (_dirty) {
      _dirty = false;
      _restart();
    }
    // One step of each lane a frame, from the tape; both start again at its
    // end.
    if (_upperPlay.isFinished) _restart();
    for (final (InputTapePlayback play, InputState input, _Ball ball)
        in <(InputTapePlayback, InputState, _Ball)>[
          (_upperPlay, _upperInput, _upperBall),
          (_lowerPlay, _lowerInput, _lowerBall),
        ]) {
      play.applyTo(input);
      ball.step(input);
      input.endStep();
    }
    _upper.setPosition(_upperBall.x - 3.0, 0.25, -0.6);
    _lowerNode.setPosition(_lowerBall.x - 3.0, 0.25, 0.6);
  }

  @override
  List<DemoControl> controls(DemoContext context) => <DemoControl>[
    ToggleControl(
      'Lower lane: a softer bounce',
      value: () => planted,
      onChanged: (bool v) {
        planted = v;
        _dirty = true;
      },
    ),
  ];

  /// The four replays the page's claim is made of, as sentences.
  @visibleForTesting
  List<String> get verdicts => <String>[
    for (final _Verdict v in _verdicts()) '$v',
  ];

  List<_Verdict> _verdicts() => <_Verdict>[
    // #region check
    // This build replays its own tape: every checkpoint agrees.
    _replay(_tape, _Ball()),
    // Only some steps asked for, as `digestAt: [60, 120]` would.
    _replay(_tape, _Ball(), digestAt: <int>[60, 120]),
    // The planted change, caught at the first checkpoint after the first
    // bounce, with the one before it still agreeing.
    _replay(_tape, _Ball(restitution: _changed)),
    // A step the tape took no digest at, and a level edited since.
    _replay(_tape, _Ball(), digestAt: <int>[65]),
    _replay(_tape, _Ball(wall: 6.5)),
    // #endregion check
  ];

  @override
  void verify(Scene scene, FrameResult frame) {
    if (frame.drawCalls < 1) throw StateError('nothing reached the frame');
    if (_tape.checkpoints.steps.length != 12) {
      throw StateError('the tape should hold twelve checkpoints');
    }
    switch (_verdicts()) {
      case [
            _Agreed(steps: final all),
            _Agreed(steps: [60, 120]),
            _Diverged(step: final at, agreed: final before?),
            _Refused(reason: final noCheckpoint),
            _Refused(reason: final edited),
          ]
          when all.length == 12 &&
              before == at - 20 &&
              noCheckpoint.contains('no checkpoint at step 65') &&
              edited.contains('level has changed'):
        // The planted change only matters at a wall, so the replay has to
        // agree through the steps before the first bounce.
        final _Ball probe = _Ball()..restore(_tape.start);
        final InputState input = InputState();
        final InputTapePlayback play = InputTapePlayback(_tape.tape);
        var firstBounce = 0;
        for (var step = 1; probe.bounces == 0; step++) {
          play.applyTo(input);
          probe.step(input);
          input.endStep();
          firstBounce = step;
        }
        if (before >= firstBounce || at < firstBounce) {
          throw StateError(
            'the bounce is at step $firstBounce, but the replay parted '
            'between $before and $at',
          );
        }
      case final List<_Verdict> other:
        throw StateError('the replays came to $other');
    }
  }
}

/// A `Vector4` holding a colour sRGB-encoded, as the linear colour it names.
LinearColor _fromSrgb(Vector4 c) => LinearColor.fromSrgb(c.x, c.y, c.z, c.w);
