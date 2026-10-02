/// N7: a run sent with consent is played again here, kept as what it did, and
/// binned into the heatmap the editor draws.
///
///     dart test test/telemetry_routes_test.dart
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter3d_models/src/http/telemetry_routes.dart';
import 'package:flutter3d_models/src/telemetry/telemetry_service.dart';
import 'package:flutter3d_models/src/telemetry/telemetry_store.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

/// A body that walks as the stick says: past x = 4 it has won, below x = -2
/// it has lost.
final class _Walk implements HeadlessRun {
  _Walk(this.input);

  final InputState input;
  final Vector3 _at = Vector3.zero();

  @override
  RunOutcome outcome = RunOutcome.playing;

  @override
  void step(double dt) {
    if (outcome.isOver) return;
    _at
      ..x += input.moveAxis.x * 3.0 * dt
      ..z += input.moveAxis.y * 3.0 * dt;
    if (_at.x > 4.0) outcome = RunOutcome.won;
    if (_at.x < -2.0) outcome = RunOutcome.lost;
  }

  @override
  Snapshot save() => Snapshot(<String, Object?>{
    'x': _at.x,
    'z': _at.z,
    'outcome': outcome.name,
  });

  @override
  Vector3 get position => _at;

  @override
  void eye(Vector3 out) => out.setFrom(_at);

  @override
  void aim(Vector3 out) => out.setValues(1.0, 0.0, 0.0);

  @override
  String get summary => 'at ${_at.x}';

  @override
  Map<String, Object?> get reading => <String, Object?>{'x': _at.x};
}

final class _WalkGame implements HeadlessGame {
  const _WalkGame();

  @override
  String get name => 'walk';

  @override
  Map<String, GameAction> get buttons => const <String, GameAction>{};

  @override
  EntityRegistry registry() => EntityRegistry(const <EntityKind>[]);

  @override
  HeadlessRun start(Level level, CollisionWorld world, InputState input) =>
      _Walk(input);
}

Level _level() => Level(
  name: 'strip',
  materials: <String, LevelMaterial>{'stone': LevelMaterial()},
  brushes: <Brush>[
    Brush(
      centre: Vector3(0.0, -0.5, 0.0),
      size: Vector3(20.0, 1.0, 4.0),
      material: 'stone',
    ),
  ],
  entities: const <EntityDef>[],
);

Demo _record({required double stick, int steps = 120}) {
  final level = _level();
  final input = InputState();
  final world = CollisionWorld();
  level.addTo(world);
  final run = const _WalkGame().start(level, world, input);
  final start = run.save();
  final recorder = InputTapeRecorder(seed: 1);
  final trace = DigestTrace(every: 10);
  for (var step = 1; step <= steps; step++) {
    input.setStickAxis(stick, 0.0);
    recorder.record(input);
    input.beginStep();
    run.step(1.0 / 60.0);
    trace.observe(step, run.save().toJson());
    input.endStep();
  }
  return Demo(
    level: 'levels/strip.json',
    levelHash: level.digestHex,
    start: start,
    tape: recorder.tape,
    buildStamp: 'test',
    checkpoints: trace,
  );
}

String _upload(Demo demo, {String game = 'walk'}) => jsonEncode(
  TelemetryUpload.prepare(
    game: game,
    demo: demo,
    consent: TelemetryConsent.granted(
      policy: '2026-10',
      at: DateTime.utc(2026, 10, 1),
    ),
    policy: '2026-10',
  ).upload!.toJson(),
);

typedef _Server = ({MemoryTelemetryStore store, Handler handler});

_Server _server({Map<String, HeadlessGame>? games}) {
  final store = MemoryTelemetryStore();
  final service = TelemetryService(
    games: games ?? const <String, HeadlessGame>{'walk': _WalkGame()},
    levels: <String, Level>{_level().digestHex: _level()},
    store: store,
    sampleEvery: 20,
  );
  return (
    store: store,
    // Through the mount `app.dart` uses, so the prefix is tested too.
    handler: (Router()..mount('/api/telemetry/', telemetryRoutes(service).call))
        .call,
  );
}

Future<(int, Map<String, Object?>)> _call(
  _Server server,
  String method,
  String path, [
  String? body,
]) async {
  final response = await server.handler(
    Request(
      method,
      Uri.parse('http://localhost/api/telemetry$path'),
      body: body,
    ),
  );
  return (
    response.statusCode,
    jsonDecode(await response.readAsString()) as Map<String, Object?>,
  );
}

void main() {
  test('a run with consent is played again, kept as its trail, binned, and '
      'erased with its key', () async {
    // Mutation: storing the client's claim instead of the replay's outcome
    // would keep a run nobody re-simulated; erasing without the key would
    // let anybody delete anybody's run.
    final server = _server();

    final (status, receipt) = await _call(
      server,
      'POST',
      '/runs',
      _upload(_record(stick: -1.0)),
    );
    expect(status, 201, reason: '${receipt['says']}');
    expect(receipt['says'], contains('the input itself was not kept'));
    final run = receipt['run']! as int;
    final key = receipt['eraseKey']! as String;
    final kept = server.store.rows[run]!;
    expect(kept.outcome, 'lost');
    expect(kept.trail.last.$1, lessThan(-2.0));
    expect(kept.eraseKeySha256, isNot(key));
    expect(kept.policy, '2026-10');

    await _call(server, 'POST', '/runs', _upload(_record(stick: 1.0)));
    final (_, map) = await _call(
      server,
      'GET',
      '/heatmap?level=${_level().digestHex}&cell=2',
    );
    final heatmap = Heatmap.fromJson(map);
    expect(heatmap.outcomes, <String, int>{
      'won': 1,
      'lost': 1,
      'unfinished': 0,
    });
    expect(heatmap.ends.single.run, run);
    expect(heatmap.cellSize, 2.0);

    final (wrong, _) = await _call(server, 'DELETE', '/runs/$run?key=nope');
    expect(wrong, 404);
    expect(server.store.rows, contains(run));
    final (erased, _) = await _call(server, 'DELETE', '/runs/$run?key=$key');
    expect(erased, 200);
    expect(server.store.rows, isNot(contains(run)));
  });

  test('a run without consent is refused and nothing is kept', () async {
    // Mutation: a server that reads uploads whether or not they were agreed
    // to.
    final server = _server();
    final json =
        jsonDecode(_upload(_record(stick: 1.0))) as Map<String, Object?>
          ..remove('consent');

    final (status, answer) = await _call(
      server,
      'POST',
      '/runs',
      jsonEncode(json),
    );

    expect(status, 400);
    expect(answer['says'], contains('no consent'));
    expect(server.store.rows, isEmpty);
  });

  test(
    'a run of a game or a level this server lacks is refused by name',
    () async {
      final server = _server();

      final (game, gameAnswer) = await _call(
        server,
        'POST',
        '/runs',
        _upload(_record(stick: 1.0), game: 'kart'),
      );
      expect(game, 422);
      expect(gameAnswer['says'], 'this server plays no kart; it plays walk');

      final demo = _record(stick: 1.0);
      final elsewhere = Demo(
        level: 'levels/other.json',
        levelHash: '0badc0de',
        start: demo.start,
        tape: demo.tape,
        buildStamp: demo.buildStamp,
        checkpoints: demo.checkpoints,
      );
      final (level, levelAnswer) = await _call(
        server,
        'POST',
        '/runs',
        _upload(elsewhere),
      );
      expect(level, 422);
      expect(levelAnswer['says'], contains('no level with hash 0badc0de'));
      expect(server.store.rows, isEmpty);
    },
  );

  test('a tape edited after it was recorded is refused at the step it parts '
      'from the run', () async {
    // Mutation: keeping a run whose replay diverged would put a trail
    // nobody played into the heatmap.
    final server = _server();
    final honest = _record(stick: 1.0);
    final forged = Demo(
      level: honest.level,
      levelHash: honest.levelHash,
      start: honest.start,
      tape: InputTape(
        seed: 1,
        frames: <InputFrame>[
          ...honest.tape.frames.take(30),
          const InputFrame(stickX: -1.0),
          ...honest.tape.frames.skip(31),
        ],
      ),
      buildStamp: honest.buildStamp,
      checkpoints: honest.checkpoints,
    );

    final (status, answer) = await _call(
      server,
      'POST',
      '/runs',
      _upload(forged),
    );

    expect(status, 422);
    expect(answer['says'], contains('parts from the run at step 40'));
    expect(answer['says'], contains('nothing was kept'));
    expect(server.store.rows, isEmpty);
  });

  test('a server with no game says so rather than taking runs', () async {
    final server = _server(games: const <String, HeadlessGame>{});
    final (status, answer) = await _call(
      server,
      'POST',
      '/runs',
      _upload(_record(stick: 1.0)),
    );
    expect(status, 503);
    expect(answer['says'], contains('no game'));
  });

  test('a heatmap names its level and a cell it can draw', () async {
    final server = _server();
    final (none, _) = await _call(server, 'GET', '/heatmap');
    expect(none, 400);
    final (bad, answer) = await _call(server, 'GET', '/heatmap?level=a&cell=0');
    expect(bad, 400);
    expect(answer['says'], contains('"0"'));
    final (empty, map) = await _call(server, 'GET', '/heatmap?level=a');
    expect(empty, 200);
    expect(Heatmap.fromJson(map).runs, 0);
  });

  test('levels are read from a directory by digest, and a broken file is '
      'named rather than stopping the rest', () {
    final folder = Directory.systemTemp.createTempSync('telemetry_levels');
    addTearDown(() => folder.deleteSync(recursive: true));
    File(
      '${folder.path}/strip.json',
    ).writeAsStringSync(jsonEncode(_level().toJson()));
    File('${folder.path}/broken.json').writeAsStringSync('{');

    final (levels, problems) = readTelemetryLevels(folder.path);

    expect(levels.keys, <String>[_level().digestHex]);
    expect(problems.single, contains('broken.json'));
  });
}
