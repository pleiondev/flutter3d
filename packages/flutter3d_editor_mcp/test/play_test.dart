/// `HR5` for an agent: Play through the server's tools, over a
/// `flutter run --machine` of the test's own making.
///
///     dart test test/play_test.dart
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter3d_editor_core/flutter3d_editor_core.dart';
import 'package:flutter3d_editor_mcp/flutter3d_editor_mcp.dart';
import 'package:flutter3d_editor_play/flutter3d_editor_play.dart';
import 'package:flutter3d_editor_play/testing.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart'
    show Demo, DigestTrace, InputFrame, InputTape, Snapshot;
import 'package:test/test.dart';

const String _level = '''
{
  "version": 1,
  "materials": {"stone": {"baseColor": [0.5, 0.5, 0.5, 1]}},
  "brushes": [{"at": [0, 0, 0], "size": [4, 1, 4], "material": "stone"}]
}
''';

/// A session on a level in a project at `/game`, whose runs are fake, and
/// what the game was sent; [games] are the VM services of its runs, one per
/// `play`, for a test that has the game post events.
({
  EditorSession session,
  List<FakeFlutterTool> tools,
  List<FakeGame> games,
  List<String> pushed,
  List<String?> devices,
})
_session({
  String levelPath = '/game/assets/levels/one.json',
  GameAsk? ask,
  String Function(String path)? root,
}) {
  final tools = <FakeFlutterTool>[];
  final games = <FakeGame>[];
  final pushed = <String>[];
  final devices = <String?>[];
  final play = PlaySession(
    levelPath: levelPath,
    projectRootOf:
        root ?? (String path) => path.startsWith('/game/') ? '/game' : null,
    newRun: (String root, String? device) {
      devices.add(device);
      final game = FakeGame();
      games.add(game);
      final fake = fakeFlutterRun(
        projectRoot: root,
        device: device,
        game: game,
      );
      tools.add(fake.tool);
      return fake.run;
    },
    devices: () async => const <FlutterDevice>[
      FlutterDevice(id: 'macos', name: 'macOS', platform: 'darwin'),
    ],
    push: (String vmService, String level) async {
      pushed.add(level);
      return <String, Object?>{
        'diff': <String, Object?>{'fog': true},
      };
    },
    waitFor: const Duration(seconds: 5),
    ask: ask ?? callGameExtension,
  );
  return (
    session: EditorSession(Editing.parse(_level, path: levelPath), play: play),
    tools: tools,
    games: games,
    pushed: pushed,
    devices: devices,
  );
}

Future<Answer> _call(
  EditorSession session,
  String name, [
  Map<String, Object?> arguments = const <String, Object?>{},
]) async {
  final answer = await editorTools
      .firstWhere((EditorTool it) => it.name == name)
      .run(session, arguments);
  return (did: answer.did, says: answer.says);
}

/// `play`, answered by the tool as a game coming up.
Future<Answer> _played(
  ({
    EditorSession session,
    List<FakeFlutterTool> tools,
    List<FakeGame> games,
    List<String> pushed,
    List<String?> devices,
  })
  it, {
  String? device,
}) async {
  final answer = _call(it.session, 'play', <String, Object?>{
    'device': ?device,
  });
  await pumpEventQueue();
  it.tools.last
    ..say('Launching lib/main.dart')
    ..running();
  return answer;
}

void main() {
  test('a level outside any project has nothing to play', () async {
    final it = _session(levelPath: '/elsewhere/one.json');
    final answer = await _call(it.session, 'play');
    expect(answer.did, isFalse);
    expect(answer.says, contains('not inside a Flutter project'));
    expect(it.tools, isEmpty);
  });

  test('play waits for the game and says where it runs', () async {
    final it = _session();
    final answer = await _played(it, device: 'macos');

    expect(answer.did, isTrue);
    expect(answer.says, contains('running /game on macos'));
    expect(answer.says, contains('ws://game'));
    expect(answer.says, contains('Launching lib/main.dart'));
    expect(it.devices, <String?>['macos']);

    final status = await _call(it.session, 'play_status');
    expect(status.says, contains('running /game'));
  });

  test('a game that fails to build is a refusal with its console', () async {
    final it = _session();
    final answer = _call(it.session, 'play');
    await pumpEventQueue();
    it.tools.last
      ..say('lib/main.dart:3: Error: expected a semicolon')
      ..exit(1);

    final said = await answer;
    expect(said.did, isFalse);
    expect(said.says, contains('stopped (exit code 1)'));
    expect(said.says, contains('expected a semicolon'));
  });

  test('a reload is the tool\'s, and so is its answer', () async {
    final it = _session();
    await _played(it);

    final reload = _call(it.session, 'play_swap');
    await pumpEventQueue();
    final sent = it.tools.last.sent.single;
    expect(sent['method'], 'app.restart');
    expect((sent['params']! as Map)['fullRestart'], isFalse);
    it.tools.last.answer(0, <String, Object?>{
      'code': 0,
      'message': 'Reloaded 3 of 812 libraries',
    });

    final said = await reload;
    expect(said.did, isTrue);
    expect(said.says, 'hot swap: Reloaded 3 of 812 libraries');
  });

  group('what the game posts', () {
    /// `play_events` from [since], read back.
    Future<Map<String, Object?>> events(
      EditorSession session,
      int since, {
      List<String>? kinds,
    }) async {
      final answer = await _call(session, 'play_events', <String, Object?>{
        'since': since,
        'kinds': ?kinds,
      });
      expect(answer.did, isTrue, reason: answer.says);
      return jsonDecode(answer.says) as Map<String, Object?>;
    }

    List<Object?> kindsOf(Map<String, Object?> read) => <Object?>[
      for (final event in read['events']! as List<Object?>)
        (event! as Map<String, Object?>)['kind'],
    ];

    test('reaches play_events in order, and the cursor moves on', () async {
      final it = _session();
      await _played(it);
      await pumpEventQueue();
      final game = it.games.single
        ..posts('flutter3d.level.loaded', <String, Object?>{'level': 'crypt'})
        ..posts('flutter3d.pickup.taken', <String, Object?>{'gift': 'key'});
      await pumpEventQueue();

      final first = await events(it.session, 0);
      expect(kindsOf(first), <String>['level.loaded', 'pickup.taken']);
      expect(
        ((first['events']! as List<Object?>).first!
            as Map<String, Object?>)['data'],
        <String, Object?>{'level': 'crypt'},
      );
      expect(first['next'], 2);

      game
        ..posts('flutter3d.player.died')
        ..posts('flutter3d.player.respawned');
      await pumpEventQueue();

      // Mutation: answering from the start rather than the cursor gives the
      // level and the pickup again.
      final second = await events(it.session, first['next']! as int);
      expect(kindsOf(second), <String>['player.died', 'player.respawned']);
      expect(second['next'], 4);
      expect(kindsOf(await events(it.session, 4)), isEmpty);

      expect(
        kindsOf(await events(it.session, 0, kinds: <String>['player.died'])),
        <String>['player.died'],
      );
    });

    test('a cursor carries through a stop and a new play', () async {
      final it = _session();
      await _played(it);
      await pumpEventQueue();
      it.games.single
        ..posts('flutter3d.level.loaded')
        ..posts('flutter3d.player.died');
      await pumpEventQueue();
      final before = await events(it.session, 0);
      expect(before['next'], 2);

      it.tools.single.exit(0);
      await pumpEventQueue();
      await _played(it);
      await pumpEventQueue();
      it.games.last.posts('flutter3d.level.loaded');
      await pumpEventQueue();

      // Mutation: drop `_postedBefore` and the new run's first event is
      // number 1 again, which the old cursor 2 has already passed.
      final after = await events(it.session, before['next']! as int);
      expect(kindsOf(after), <String>['level.loaded']);
      expect(after['next'], 3);
    });

    test('nothing running has nothing to say', () async {
      final it = _session();
      final answer = await _call(it.session, 'play_events');
      expect(answer.did, isFalse);
      expect(answer.says, contains('call play'));
    });
  });

  test('nothing running is nothing to reload or stop', () async {
    final it = _session();
    expect((await _call(it.session, 'play_swap')).did, isFalse);
    expect((await _call(it.session, 'play_stop')).did, isFalse);
    expect(
      (await _call(it.session, 'play_status')).says,
      contains('not running'),
    );
  });

  test('another device while one runs is refused, not a second game', () async {
    final it = _session();
    await _played(it, device: 'macos');

    final again = await _call(it.session, 'play', <String, Object?>{
      'device': 'chrome',
    });
    expect(again.did, isFalse);
    expect(again.says, contains('play_stop'));
    expect(it.tools, hasLength(1));
  });

  test('a save reaches the running game; a copy does not', () async {
    final directory = await Directory.systemTemp.createTemp('play_test');
    addTearDown(() => directory.delete(recursive: true));
    final path = '${directory.path}/one.json';
    File(path).writeAsStringSync(_level);
    final it = _session(levelPath: path);
    // The temporary directory is not under `/game`: the session's project
    // is found by path, so a level there is played by pointing at it.
    final play = PlaySession(
      levelPath: path,
      projectRootOf: (String _) => directory.path,
      newRun: (String root, String? device) {
        final fake = fakeFlutterRun(projectRoot: root, device: device);
        it.tools.add(fake.tool);
        return fake.run;
      },
      push: (String vmService, String level) async {
        it.pushed.add(level);
        return <String, Object?>{
          'diff': <String, Object?>{'fog': true},
        };
      },
      waitFor: const Duration(seconds: 5),
    );
    final session = EditorSession(
      Editing.parse(_level, path: path),
      play: play,
    );
    final started = _call(session, 'play');
    await pumpEventQueue();
    it.tools.last.running();
    await started;

    final saved = await _call(session, 'save');
    expect(saved.says, contains('the game took the new look'));
    expect(it.pushed, hasLength(1));

    await _call(session, 'save', <String, Object?>{
      'path': '${directory.path}/copy.json',
    });
    expect(it.pushed, hasLength(1), reason: 'the game plays the original');
  });

  test('the devices are listed with the id play takes', () async {
    final it = _session();
    final answer = await _call(it.session, 'play_devices');
    expect(answer.says, 'macOS (macos, darwin)');
  });

  group('the frame the running game drew', () {
    test(
      'render tools ask the game play started, and say its answer',
      () async {
        final asked = <String>[];
        final it = _session(
          ask:
              (
                String vmService,
                String method, {
                Map<String, String> args = const <String, String>{},
              }) async {
                asked.add('$vmService $method $args');
                return switch (method) {
                  'ext.flutter3d.render.pick' => (
                    json: <String, Object?>{
                      'frame': 3,
                      'node': 'crypt_wall',
                      'draws': <int>[4, 9],
                    },
                    refused: null,
                  ),
                  _ => (json: null, refused: 'there is no draw 40'),
                };
              },
        );
        // Nothing running, nothing to ask.
        final before = await _call(it.session, 'render_pick', <String, Object?>{
          'x': 1,
          'y': 2,
        });
        expect(before.did, isFalse);
        expect(before.says, contains('call play first'));

        await _played(it);
        final picked = await _call(it.session, 'render_pick', <String, Object?>{
          'x': 640,
          'y': 360,
        });
        expect(picked.did, isTrue, reason: picked.says);
        expect(picked.says, contains('crypt_wall'));
        // Mutation: asking with the tool's own vmService argument left in.
        expect(
          asked.single,
          endsWith('ext.flutter3d.render.pick {x: 640, y: 360}'),
        );
        // The game's refusal, in its own words.
        final refused = await _call(
          it.session,
          'render_draw',
          <String, Object?>{'index': 40},
        );
        expect(refused.did, isFalse);
        expect(refused.says, 'there is no draw 40');
        // Another game, by its address.
        await _call(it.session, 'render_stats', <String, Object?>{
          'vmService': 'ws://other/ws',
        });
        // Mutation: asking with the tool's own vmService argument left in.
        expect(asked.last, 'ws://other/ws ext.flutter3d.render.stats {}');
      },
    );

    test('the run the game kept is dropped into its test/tapes', () async {
      final project = Directory.systemTemp.createTempSync('keep_tape');
      addTearDown(() => project.deleteSync(recursive: true));
      final it = _session(
        root: (String _) => project.path,
        ask:
            (
              String vmService,
              String method, {
              Map<String, String> args = const <String, String>{},
            }) async => (
              json: <String, Object?>{
                'version': 1,
                'level': 'assets/levels/crypt.json',
                'levelHash': 'abc',
                'start': const Snapshot(<String, Object?>{}).toJson(),
                'tape': InputTape(
                  seed: 1,
                  frames: const <InputFrame>[InputFrame(), InputFrame()],
                ).toJson(),
                'buildStamp': 'dev',
                'checkpoints': DigestTrace().toJson(),
                'physics': 'native',
              },
              refused: null,
            ),
      );
      await _played(it);
      expect(
        (await _call(it.session, 'play_keep_tape', <String, Object?>{
          'name': '../out',
        })).did,
        isFalse,
      );
      final kept = await _call(it.session, 'play_keep_tape', <String, Object?>{
        'name': 'wall_clip',
      });
      expect(kept.did, isTrue, reason: kept.says);
      final file = File('${project.path}/test/tapes/wall_clip.f3drun');
      final demo = Demo.fromJson(
        jsonDecode(file.readAsStringSync()) as Map<String, Object?>,
      );
      expect(demo.steps, 2);
      expect(demo.physics, 'native');
    });
  });
}
