/// A time-travel debugger over a live run: scrub to any step the rewind
/// buffer holds and back to the present, read each entity's history as
/// lanes, branch from a scrubbed moment, and bisect two runs of one tape to
/// the step and component where they part.
///
/// Quoted by `time_travel.md` and shown whole in the Source tab.
library;

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart';
import 'package:flutter3d_showcase/src/demo/demo.dart';
import 'package:flutter3d_showcase/src/demo/scene_kit.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';

const GameAction _fire = GameAction('fire');

// #region toy
/// Three entities written one row each: a runner that follows the stick, a
/// door that opens when the runner reaches it, and a target that loses
/// health by the dice whenever fire is pressed.
///
/// [defectAt] is a planted bug: on that step, and only that one, the target
/// loses a point more. It stands for a code change or another platform, and
/// it touches one component of one entity so the bisection has something
/// definite to name.
final class _Toy {
  _Toy({this.defectAt});

  final int? defectAt;
  final GameRandom dice = GameRandom(11);
  double x = 0.0;
  bool open = false;
  int hp = 200;
  int steps = 0;

  void step(InputState input) {
    x += input.moveAxis.x * 0.05;
    if (x > 2.0) open = true;
    if (x < 1.0) open = false;
    if (input.pressed(_fire)) hp -= 1 + dice.nextInt(6);
    if (steps == defectAt) hp -= 1;
    steps++;
  }

  Snapshot save() => Snapshot(<String, Object?>{
    'entities': <String, Object?>{
      'runner': <String, Object?>{'x': x},
      'door': <String, Object?>{'open': open},
      'target': <String, Object?>{'hp': hp},
    },
    'random': dice.state,
    'steps': steps,
  });

  void restore(Snapshot snapshot) {
    final Map<String, Object?> entities = snapshot.data.object('entities')!;
    x = entities.object('runner')!.number('x');
    open = entities.object('door')!['open'] == true;
    hp = entities.object('target')!.integer('hp');
    dice.state = snapshot.data.integer('random');
    steps = snapshot.data.integer('steps');
  }
}

/// How the toy's snapshot is read as entities: one row per entity under
/// `entities`, each row's fields its components.
final EntityLayout _layout = EntityLayout.rows('entities');

/// [length] steps of input: the stick swings every second and fire is
/// pressed now and then.
InputTape _tape(int length) => InputTape(
  seed: 11,
  frames: <InputFrame>[
    for (var i = 0; i < length; i++)
      InputFrame(
        pressed: <String>[if (i % 23 == 5) _fire.name],
        released: <String>[if (i % 23 == 6) _fire.name],
        stickX: i % 120 < 60 ? 1.0 : -1.0,
      ),
  ],
);
// #endregion toy

/// A run of [steps] steps through an engine loop, with the state before
/// every step kept to hold a scrub against.
final class _Run {
  _Run(int steps) {
    // #region record
    // The toy is a part of the loop's snapshots and a system in its step;
    // the buffer is attached, so its keyframes are the loop's captures.
    loop
      ..snapshots.add(
        SnapshotPart.of(
          id: 'toy',
          capture: () => toy.save().data,
          restore: (Object? data, int _) {
            if (data is Map) {
              toy.restore(Snapshot(data.cast<String, Object?>()));
            }
          },
        ),
      )
      ..addSystem('toy', LoopPhase.rules, (_) => toy.step(input));
    rewind.attach(loop);
    loop.playback = InputTapePlayback(_tape(steps));
    for (var step = 0; step < steps; step++) {
      seen[step] = toy.save();
      loop.runSteps(1);
    }
    loop.playback = null;
    seen[steps] = toy.save();
    // #endregion record
  }

  final _Toy toy = _Toy();
  final InputState input = InputState();
  late final EngineLoop loop = EngineLoop(input: input);
  final RewindBuffer rewind = RewindBuffer(stepsPerSecond: 60, history: 10.0);
  late final RunTimeline timeline = RunTimeline(rewind: rewind, loop: loop);
  final Map<int, Snapshot> seen = <int, Snapshot>{};

  int digestNow() => StateDigest.of(toy.save().data);
  int digestSeen(int step) => StateDigest.of(seen[step]!.data);
}

final class TimeTravelDemo extends ShowcaseDemo {
  static const int _length = 300;

  /// The run the viewport shows, paused at its present.
  late final _Run _live;
  double _scrub = _length.toDouble();
  bool _dirty = true;

  late final MeshNode _runner;
  late final MeshNode _door;
  late final MeshNode _target;

  @override
  void configureView(DemoContext context) {
    context.orbit
      ..distance = 7.5
      ..pitch = 0.4
      ..yaw = 0.2;
    context.orbit.target.setValues(1.0, 0.6, 0.0);
  }

  @override
  Scene build(DemoContext context) {
    _live = _Run(_length);
    _live.timeline.pause();
    _runner = ballNode(context, 'runner', 0.3, Vector4(0.45, 0.75, 0.95, 1.0));
    _door = blockNode(
      context,
      'door',
      Vector3(0.2, 1.4, 1.2),
      Vector4(0.75, 0.55, 0.35, 1.0),
    );
    _target = blockNode(
      context,
      'target',
      Vector3(0.6, 1.0, 0.6),
      Vector4(0.9, 0.35, 0.3, 1.0),
    );
    _place();
    return sceneOf(<SceneNode>[
      floorNode(context, width: 6.0, depth: 3.0),
      _runner,
      _door,
      _target,
    ]);
  }

  void _place() {
    final _Toy toy = _live.toy;
    _runner.setPosition(toy.x - 0.5, 0.3, 0.0);
    _door.setPosition(1.5, toy.open ? 2.0 : 0.7, -0.9);
    final double h = (toy.hp / 200.0).clamp(0.05, 1.0) * 1.6;
    _target
      ..setScale(1.0, h, 1.0)
      ..setPosition(3.2, h / 2.0, 0.0);
  }

  @override
  void update(DemoContext context, double dt) {
    if (!_dirty) return;
    _dirty = false;
    // #region scrub
    // The slider is the scrubber. Any held step moves the live state there
    // and keeps the tape and the present; the right end is the present.
    final int step = _scrub.round();
    if (step >= _live.rewind.step) {
      _live.timeline.returnToPresent();
    } else {
      _live.timeline.scrubTo(step);
    }
    // #endregion scrub
    _place();
  }

  @override
  List<DemoControl> controls(DemoContext context) => <DemoControl>[
    SliderControl(
      'Scrub to step',
      min: 0,
      max: _length.toDouble(),
      divisions: _length,
      value: () => _scrub,
      onChanged: (double v) {
        _scrub = v.roundToDouble();
        _dirty = true;
      },
      format: (double v) =>
          v.round() >= _length ? 'the present' : 'before step ${v.round()}',
    ),
    ToggleControl(
      'Back to present',
      value: () => false,
      onChanged: (bool v) {
        if (!v) return;
        _scrub = _length.toDouble();
        _dirty = true;
      },
    ),
  ];

  /// Scrubs a fresh run back and forth and answers the first step whose
  /// state was not the one recorded before it, or null when every one was.
  @visibleForTesting
  static String? scrubMismatch() {
    final _Run run = _Run(_length);
    run.timeline.pause();
    // #region back-and-forth
    for (final int step in <int>[200, 240, 120, 121, 299, 0, 200]) {
      final ScrubAnswer answer = run.timeline.scrubTo(step);
      if (answer is! ScrubMoved) return 'step $step: $answer';
      if (run.digestNow() != run.digestSeen(step)) return 'step $step';
    }
    run.timeline.returnToPresent();
    if (run.digestNow() != run.digestSeen(_length)) return 'the present';
    // #endregion back-and-forth
    if (run.rewind.step != _length) return 'the tape was cut by a scrub';
    return null;
  }

  @override
  void verify(Scene scene, FrameResult frame) {
    if (frame.drawCalls < 1) throw StateError('nothing reached the frame');

    // Scrubbing back and forth lands on the state recorded before each
    // step, and the present comes back exactly.
    final String? mismatch = scrubMismatch();
    if (mismatch != null) {
      throw StateError('a scrub missed the recorded state at $mismatch');
    }

    final _Run run = _Run(_length)..timeline.pause();
    // #region tracks
    final EntityTracks tracks = run.timeline.tracks(
      layout: _layout,
      part: 'toy',
    )!;
    final List<TrackSample> door = tracks.samples('door', 'open');
    final TrackSample? hpAt150 = tracks.at('target', 'hp', 150);
    // #endregion tracks
    if (tracks.span != (first: 0, last: _length)) {
      throw StateError('the lanes cover ${tracks.span}, not 0 to $_length');
    }
    if (door.length < 3) {
      throw StateError('the door opened and closed, but its lane has $door');
    }
    final Object? hpSeen = run.seen[150]!.data
        .object('entities')!
        .object('target')!['hp'];
    if (hpAt150?.value != hpSeen) {
      throw StateError(
        'the hp lane says ${hpAt150?.value} at 150, not $hpSeen',
      );
    }
    if (run.digestNow() != run.digestSeen(_length)) {
      throw StateError('reading the lanes moved the live state');
    }

    // #region branch
    run.timeline.scrubTo(150);
    final ScrubAnswer branched = run.timeline.branchHere();
    // #endregion branch
    if (branched is! ScrubMoved ||
        run.rewind.step != 150 ||
        !run.timeline.isPaused ||
        run.digestNow() != run.digestSeen(150)) {
      throw StateError('branching at 150 did not make 150 the present');
    }

    // #region bisect
    // Two runs of one tape: this build, and one with a defect planted on
    // step 413. Each side owns its own simulation.
    ReplaySide side(_Toy toy) {
      final InputState input = InputState();
      return ReplaySide(
        start: toy.save(),
        tape: _tape(600),
        input: input,
        step: () => toy.step(input),
        restore: toy.restore,
        capture: toy.save,
      );
    }

    final TapeBisection found = bisectTapes(
      a: side(_Toy()),
      b: side(_Toy(defectAt: 413)),
      layout: _layout,
    );
    // #endregion bisect
    if (found is! TapesDiverge) throw StateError('the bisection found $found');
    // #region named
    // `step` counts steps taken, so the tape entry that differed is one less.
    if (found.step - 1 != 413 ||
        found.inputsDiffer ||
        found.component != const EntityComponent('target', 'hp') ||
        found.components.length != 1 ||
        found.probes > 12) {
      throw StateError('the bisection named the wrong place: $found');
    }
    // #endregion named
  }
}
