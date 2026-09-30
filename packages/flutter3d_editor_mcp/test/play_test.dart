/// `HR5` for an agent: Play through the server's tools, over a
/// `flutter run --machine` of the test's own making.
///
///     dart test test/play_test.dart
library;

import 'dart:io';

import 'package:flutter3d_editor_core/flutter3d_editor_core.dart';
import 'package:flutter3d_editor_mcp/flutter3d_editor_mcp.dart';
import 'package:flutter3d_editor_play/flutter3d_editor_play.dart';
import 'package:flutter3d_editor_play/testing.dart';
import 'package:test/test.dart';

const String _level = '''
{
  "version": 1,
  "materials": {"stone": {"baseColor": [0.5, 0.5, 0.5, 1]}},
  "brushes": [{"at": [0, 0, 0], "size": [4, 1, 4], "material": "stone"}]
}
''';

/// A session on a level in a project at `/game`, whose runs are fake, and
/// what the game was sent.
({
  EditorSession session,
  List<FakeFlutterTool> tools,
  List<String> pushed,
  List<String?> devices,
})
_session({String levelPath = '/game/assets/levels/one.json'}) {
  final tools = <FakeFlutterTool>[];
  final pushed = <String>[];
  final devices = <String?>[];
  final play = PlaySession(
    levelPath: levelPath,
    projectRootOf: (String path) => path.startsWith('/game/') ? '/game' : null,
    newRun: (String root, String? device) {
      devices.add(device);
      final fake = fakeFlutterRun(projectRoot: root, device: device);
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
  );
  return (
    session: EditorSession(Editing.parse(_level, path: levelPath), play: play),
    tools: tools,
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
}
