/// `HR5`: the editor runs a project through `flutter run --machine` and
/// drives it — against a process of the test's own making, which speaks the
/// daemon protocol the way the tool does.
///
///     dart test test/flutter_run_test.dart
library;

import 'dart:io';

import 'package:flutter3d_editor_play/flutter3d_editor_play.dart';
import 'package:flutter3d_editor_play/testing.dart';
import 'package:test/test.dart';

void main() {
  test('starts the tool in the project and follows it to running', () async {
    final it = fakeFlutterRun();
    await it.run.start();
    expect(it.started.single, <String>[
      '/game',
      'run',
      '--machine',
      '-d',
      'macos',
    ]);
    expect(it.run.state.value, isA<PlayStarting>());

    it.tool
      ..say('Resolving dependencies...')
      ..event('app.start', <String, Object?>{'appId': 'a1'})
      ..event('app.progress', <String, Object?>{'message': 'Building macOS'})
      ..event('app.debugPort', <String, Object?>{
        'appId': 'a1',
        'port': 8181,
        'wsUri': 'ws://127.0.0.1:8181/ws',
      })
      ..event('app.log', <String, Object?>{'log': 'flutter: hello'});
    await pumpEventQueue();

    final running = it.run.state.value as PlayRunning;
    expect(running.appId, 'a1');
    expect(running.vmService, 'ws://127.0.0.1:8181/ws');
    expect(it.run.console.value, <String>[
      'Resolving dependencies...',
      'Building macOS',
      'flutter: hello',
    ]);
  });

  test('a hot reload and a hot restart are the tool\'s own commands', () async {
    final it = fakeFlutterRun();
    await it.run.start();
    it.tool.event('app.debugPort', <String, Object?>{
      'appId': 'a1',
      'wsUri': 'ws://x',
    });
    await pumpEventQueue();

    final reload = it.run.hotSwap();
    await pumpEventQueue();
    expect(it.tool.sent.single, <String, Object?>{
      'id': 0,
      'method': 'app.restart',
      'params': <String, Object?>{
        'appId': 'a1',
        'fullRestart': false,
        'pause': false,
        'reason': 'manual',
      },
    });
    it.tool.answer(0, <String, Object?>{'code': 0, 'message': ''});
    await reload;

    final restart = it.run.hotRestart();
    await pumpEventQueue();
    expect((it.tool.sent.last['params']! as Map)['fullRestart'], isTrue);
    it.tool.answer(1, <String, Object?>{
      'code': 1,
      'message': 'Reload rejected: a const changed shape',
    });
    await restart;
    expect(it.run.console.value.last, 'Reload rejected: a const changed shape');
  });

  test('the tool exiting stops the run and fails what was waiting', () async {
    final it = fakeFlutterRun();
    await it.run.start();
    it.tool.event('app.debugPort', <String, Object?>{
      'appId': 'a1',
      'wsUri': 'ws://x',
    });
    await pumpEventQueue();

    final reload = it.run.hotSwap();
    await pumpEventQueue();
    it.tool.exit(1);

    await expectLater(reload, throwsStateError);
    expect((it.run.state.value as PlayStopped).exitCode, 1);
  });

  test(
    'the console keeps the newest lines when a game logs every frame',
    () async {
      final it = fakeFlutterRun();
      await it.run.start();
      for (var i = 0; i < FlutterRun.consoleLimit + 5; i++) {
        it.tool.say('line $i');
      }
      await pumpEventQueue();
      expect(it.run.console.value, hasLength(FlutterRun.consoleLimit));
      expect(it.run.console.value.first, 'line 5');
    },
  );

  test('a stop before the game has started ends the process', () async {
    final tool = FakeFlutterTool();
    final killed = <Process>[];
    final run = FlutterRun(
      projectRoot: '/game',
      start: (_, _) async => tool,
      kill: killed.add,
    );
    await run.start();
    await run.stop();
    // Mutation: `stop` calling `Process.kill` directly passes everything
    // else here and leaves the tool building on Windows, where the process
    // it was handed is `cmd.exe`.
    expect(killed, <Process>[tool]);
    expect(tool.sent, isEmpty);
  });

  test('on Windows a stop takes the whole tree the shell started', () {
    // Mutation: dropping `/t` ends `cmd.exe` and orphans the tool; dropping
    // the Windows branch altogether does the same through `Process.kill`.
    expect(treeKillCommand(42, windows: true), <String>[
      'taskkill',
      '/pid',
      '42',
      '/t',
      '/f',
    ]);
    expect(treeKillCommand(42, windows: false), isNull);
  });

  test('a level is run as part of the nearest project above it', () {
    final projects = <String>{'/work/game'};
    bool hasPubspec(String directory) => projects.contains(directory);

    expect(
      projectRootFor(
        '/work/game/assets/levels/one.json',
        hasPubspec: hasPubspec,
      ),
      '/work/game',
    );
    expect(
      projectRootFor('/elsewhere/one.json', hasPubspec: hasPubspec),
      isNull,
    );
  });

  test(
    'a device id the shell would read is refused before anything starts',
    () async {
      // On Windows `flutter` is `flutter.bat` and its arguments pass through
      // `cmd.exe`, so each of these runs a second command there.
      for (final payload in <String>[
        'macos & calc',
        'macos" & calc & "',
        'macos | calc',
        'macos^&calc',
        '%COMSPEC%',
        '-d',
        'x>out.txt',
        '',
      ]) {
        final it = fakeFlutterRun(device: payload);
        // Mutation: start with `-d` and whatever the id is. The payload
        // reaches the shell as part of the command line.
        await it.run.start();
        expect(it.started, isEmpty, reason: payload);
        expect(it.run.state.value, isA<PlayStopped>(), reason: payload);
        expect(it.run.console.value.single, contains('refused to run on'));
      }
      for (final id in <String>[
        'macos',
        'emulator-5554',
        '00008030-001A35E22E38802E',
        '192.168.1.5:5555',
        'adb-R5CT-x._adb-tls-connect._tcp',
      ]) {
        expect(isFlutterDeviceId(id), isTrue, reason: id);
      }
    },
  );
}
