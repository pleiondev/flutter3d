/// A run shared behind a short code and opened again as a ghost to race:
/// the level, its hash and the run go into a bundle, the bundle goes through
/// a sharing service, and what comes back is played to a pose track.
///
/// **The service is a map in this process.** `RunService` takes the
/// function that carries its requests, so this page hands it one that
/// answers the `v1/shares` routes from memory, in the shapes the reference
/// server in `cloud/server` answers them. Nothing leaves the machine.
///
/// Quoted by `sharing_ghosts.md` and shown whole in the Source tab.
library;

import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_showcase/src/demo/demo.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';

// #region game
/// A runner on a strip, steered by the stick. The run is won past the far
/// end of the level's track, so the level is part of the run.
final class _Runner extends HeadlessRun {
  _Runner(this.input, this.finish);

  final InputState input;
  final double finish;
  final Vector3 _at = Vector3.zero();

  @override
  RunOutcome outcome = RunOutcome.playing;

  @override
  void step(double dt) {
    if (outcome.isOver) return;
    _at
      ..x += input.moveAxis.x * 4.0 * dt
      ..z += input.moveAxis.y * 4.0 * dt;
    if (_at.x >= finish) outcome = RunOutcome.won;
  }

  @override
  Snapshot save() => Snapshot(<String, Object?>{
    'x': _at.x,
    'z': _at.z,
    'outcome': outcome.name,
  });

  @override
  WorldPosition get position => _at.toWorldPosition();

  @override
  WorldPosition get eye => _at.toWorldPosition();

  @override
  void aim(Vector3 out) => out.setValues(1.0, 0.0, 0.0);

  @override
  String get summary => 'at ${_at.x.toStringAsFixed(2)}';

  @override
  Map<String, Object?> get reading => <String, Object?>{'x': _at.x};
}

/// The track, as a level document: one brush, whose far end is the finish.
Level _track({double length = 16.0}) => Level(
  name: 'strip',
  materials: <String, LevelMaterial>{'stone': LevelMaterial()},
  brushes: <Brush>[
    Brush(
      center: Vector3(length / 2, -0.25, 0.0),
      size: Vector3(length, 0.5, 4.0),
      material: 'stone',
    ),
  ],
);

_Runner _start(Level level, InputState input) {
  final Brush strip = level.brushes.first;
  return _Runner(input, strip.center.x + strip.size.x / 2);
}
// #endregion game

// #region record
/// Plays [level] the way a person might — weaving down the strip — and
/// writes it down as a game does: the tape before each step, a checkpoint
/// after it. [steps] gets where the runner was after each step.
Demo _record(Level level, List<Vector3> steps) {
  final input = InputState();
  final run = _start(level, input);
  final start = run.save();
  final recorder = InputTapeRecorder(seed: 1);
  final trace = DigestTrace(every: 10);
  steps.add(run.position.toVector3Relative(WorldPosition.origin));
  for (var step = 1; !run.outcome.isOver; step++) {
    // Inside the unit circle, so the input never rescales the stick and
    // the tape holds exactly what the step read.
    input.setStickAxis(0.8, 0.55 * math.sin(step * 0.06));
    recorder.record(input);
    input.beginStep();
    run.step(1.0 / 60.0);
    trace.observe(step, run.save().toJson());
    input.endStep();
    steps.add(run.position.toVector3Relative(WorldPosition.origin));
  }
  return Demo(
    level: 'levels/strip.json',
    levelHash: level.digestHex,
    start: start,
    tape: recorder.tape,
    buildStamp: 'showcase',
    checkpoints: trace,
  );
}
// #endregion record

// #region service
/// The `v1/shares` routes, answered from a map: a bundle filed under a code
/// made from its bytes, and opened by that code.
RunTransport _inMemory(Map<String, Map<String, Object?>> store) =>
    (RunRequest request) async {
      final List<String> path = request.uri.pathSegments;
      if (request.method == 'POST' && path.last == 'shares') {
        final json = jsonDecode(request.body!) as Map<String, Object?>;
        try {
          // The server reads the bundle the way the client wrote it, and
          // refuses one whose run is for another level just the same.
          ShareBundle.fromJson(json);
        } on ShareFormatException catch (e) {
          return RunResponse(422, jsonEncode({'message': e.message}));
        }
        final String address = contentDigestHex(json);
        final String code = address.substring(0, 6).toUpperCase();
        store[code] = json;
        return RunResponse(
          201,
          jsonEncode({
            'code': code,
            'address': address,
            'status': ShareStatus.published.name,
          }),
        );
      }
      if (request.method == 'GET' && path.length >= 2) {
        final Map<String, Object?>? bundle = store[path.last];
        return bundle == null
            ? RunResponse(
                404,
                jsonEncode({'message': 'no share "${path.last}"'}),
              )
            : RunResponse(200, jsonEncode({'bundle': bundle}));
      }
      return const RunResponse(404, '{"message":"no such route"}');
    };
// #endregion service

// #region ghost
/// Where the runner of a shared run was: [demo]'s tape played into a fresh
/// run of [level], the position written down as it goes. Refused, with the
/// reason, when the run was recorded in another version of the level.
({Tape? ghost, String says}) _ghostOf(Level level, Demo demo) {
  if (demo.levelHash != level.digestHex) {
    return (
      ghost: null,
      says: 'the run was made in another version of this level',
    );
  }
  final input = InputState();
  final run = _start(level, input);
  final recorder = Recorder(hz: 30.0);
  const dt = 1.0 / 60.0;
  final playback = InputTapePlayback(demo.tape);
  var step = 0;
  recorder.tick(
    0.0,
    position: run.position.toVector3Relative(WorldPosition.origin),
    yaw: 0.0,
  );
  while (!playback.isFinished) {
    playback.applyTo(input);
    input.beginStep();
    run.step(dt);
    input.endStep();
    step++;
    recorder.tick(
      step * dt,
      position: run.position.toVector3Relative(WorldPosition.origin),
      yaw: 0.0,
    );
  }
  return (
    ghost: recorder.finish(step * dt),
    says: 'a ghost of ${(step * dt).toStringAsFixed(1)} s',
  );
}
// #endregion ghost

final class SharingGhostsDemo extends ShowcaseDemo {
  final List<Vector3> _original = <Vector3>[];
  final Map<String, Map<String, Object?>> _store =
      <String, Map<String, Object?>>{};
  late final Level _level;
  late final Level _edited;
  String _code = '';
  Tape? _ghost;
  String _ghostSays = '';
  String _bundleRefused = '';
  String _editedSays = '';

  /// Open the shared run in a version of the level with a longer track.
  bool edited = false;

  late final MeshNode _ghostNode;
  late final MeshNode _you;
  final Pose _at = Pose();
  double _clock = 0.0;
  late _Runner _live;
  late InputState _liveInput;

  @override
  void configureView(DemoContext context) {
    context.orbit
      ..distance = 20.0
      ..pitch = 0.55
      ..yaw = 0.25;
    context.orbit.target.setValues(8.0, 0.0, 0.0);
  }

  @override
  Future<void> prepare(DemoContext context) async {
    _level = _track();
    _edited = _track(length: 18.0);
    final Demo run = _record(_level, _original);

    // #region share
    final service = RunService(
      base: Uri.parse('https://shares.invalid/'),
      transport: _inMemory(_store),
    );
    final ServiceAnswer<SharedBundle> filed = await service.share(
      ShareBundle(game: 'showcase-strip', level: _level.toJson(), run: run),
    );
    if (filed case ServiceDone(value: final SharedBundle shared)) {
      _code = shared.code;
    }
    // A friend types the code in.
    final ServiceAnswer<ShareBundle> opened = await service.open(_code);
    if (opened case ServiceDone(value: final ShareBundle bundle)) {
      final (:ghost, :says) = _ghostOf(
        Level.fromJson(bundle.level),
        bundle.run!,
      );
      _ghost = ghost;
      _ghostSays = says;
    }
    // #endregion share

    // #region refuse
    // The same run with the track made longer: refused before it leaves,
    // and refused again by whoever opens it in that level.
    try {
      ShareBundle(game: 'showcase-strip', level: _edited.toJson(), run: run);
    } on ShareFormatException catch (e) {
      _bundleRefused = e.message;
    }
    _editedSays = _ghostOf(_edited, run).says;
    // #endregion refuse
  }

  @override
  Scene build(DemoContext context) {
    _ghostNode = MeshNode(
      DeviceMesh.upload(
        context.device,
        SphereShape(segments: 20, rings: 10, radius: 0.45).build(),
      ),
      RenderMaterial(
        name: 'ghost',
        baseColor: LinearColor.fromSrgb(0.65, 0.85, 1.0, 0.4),
        alphaMode: MaterialAlphaMode.blend,
        depthWrite: false,
        lighting: LightingModel.unlit,
      ),
      name: 'ghost',
    );
    _you = MeshNode(
      DeviceMesh.upload(
        context.device,
        SphereShape(segments: 20, rings: 10, radius: 0.45).build(),
      ),
      RenderMaterial(
        name: 'you',
        baseColor: LinearColor.fromSrgb(0.9, 0.55, 0.25, 1.0),
      ),
      name: 'you',
    );
    _restart();
    final Brush strip = _level.brushes.first;
    return Scene()
      ..ambientColor = LinearColor(0.5, 0.55, 0.65)
      ..ambientIntensity = 0.35 * Photometric.legacyUnit
      ..add(
        MeshNode(
          DeviceMesh.upload(
            context.device,
            CuboidShape(size: strip.size).build(),
          ),
          RenderMaterial(
            name: 'track',
            baseColor: LinearColor.fromSrgb(0.4, 0.42, 0.45, 1.0),
          ),
          name: 'track',
        )..setPositionFrom(strip.center),
      )
      ..add(
        MeshNode(
          DeviceMesh.upload(
            context.device,
            CuboidShape(size: Vector3(0.2, 0.05, 4.0)).build(),
          ),
          RenderMaterial(
            name: 'finish',
            baseColor: LinearColor.fromSrgb(0.9, 0.9, 0.9, 1.0),
          ),
          name: 'finish',
        )..setPosition(strip.center.x + strip.size.x / 2 - 0.1, 0.02, 0.0),
      )
      ..add(_you)
      ..add(_ghostNode)
      ..add(
        LightNode(name: 'sun', intensity: 2.6 * Photometric.legacyUnit)
          ..setLocalForward(Vector3(-0.35, -1.0, -0.45)),
      );
  }

  void _restart() {
    _clock = 0.0;
    _liveInput = InputState();
    _live = _start(_level, _liveInput);
  }

  @override
  void update(DemoContext context, double dt) {
    _clock += dt;
    // You run straight, and a little slower than the weaving ghost.
    _liveInput.setStickAxis(0.75, 0.0);
    _live.step(dt);
    _you.setPosition(_live.position.x, 0.45, _live.position.z + 1.0);
    final Tape? ghost = edited ? null : _ghost;
    if (ghost != null && Playback(ghost).sampleAt(_clock, _at)) {
      _ghostNode
        ..isVisible = true
        ..setPosition(_at.position.x, 0.45, _at.position.z - 1.0);
    } else {
      _ghostNode.isVisible = false;
    }
    if (_clock > 6.0) _restart();
  }

  @override
  List<DemoControl> controls(DemoContext context) => <DemoControl>[
    ToggleControl(
      edited
          ? 'Open it in the longer track: $_editedSays'
          : 'Open it in the longer track (code $_code: $_ghostSays)',
      value: () => edited,
      onChanged: (bool v) {
        edited = v;
        _restart();
      },
    ),
  ];

  @override
  void verify(Scene scene, FrameResult frame) {
    // #region check
    // Filed, opened by its code, and played to a ghost.
    final Tape? ghost = _ghost;
    if (_code.length != 6 || ghost == null) {
      throw StateError('the run did not come back as a ghost: "$_ghostSays"');
    }
    // A run for another version of the level is refused, both ways.
    if (!_bundleRefused.contains('another version of the level') ||
        !_editedSays.contains('another version')) {
      throw StateError('the edited level was not refused');
    }
    // The ghost is where the original runner was, to the bit, at every
    // sample, and it ends where the run ended.
    for (final Pose pose in ghost.poses) {
      final Vector3 was = _original[(pose.time * 60.0).round()];
      if (pose.position != was) {
        throw StateError(
          'at ${pose.time} s the ghost is at ${pose.position}, '
          'the run was at $was',
        );
      }
    }
    // Thirty samples a second, so the last is within a step of the line.
    if (ghost.poses.last.position.x < 15.9) {
      throw StateError('the ghost did not reach the finish');
    }
    // #endregion check
    if (frame.drawCalls < 3) throw StateError('the race was not drawn');
  }
}
