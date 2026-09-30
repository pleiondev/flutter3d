/// `HR5`: the editor runs a project through `flutter run --machine` and
/// drives it — against a process of the test's own making, which speaks the
/// daemon protocol the way the tool does.
///
///     flutter test test/flutter_run_test.dart
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter3d_editor/src/play/flutter_run.dart';
import 'package:flutter3d_editor/src/play/play_screen.dart';
import 'package:flutter_test/flutter_test.dart';

/// A `flutter run --machine` that says what [say] is given and records what
/// it is sent.
final class _Tool implements Process {
  final StreamController<List<int>> _out = StreamController<List<int>>();
  final StreamController<List<int>> _err = StreamController<List<int>>();
  final Completer<int> _exit = Completer<int>();
  final List<Map<String, Object?>> sent = <Map<String, Object?>>[];
  late final IOSink _in = IOSink(_Sent(this));

  void say(String line) => _out.add(utf8.encode('$line\n'));

  void event(String event, Map<String, Object?> params) => say(
    jsonEncode(<Object?>[
      <String, Object?>{'event': event, 'params': params},
    ]),
  );

  void answer(int id, Object? result) => say(
    jsonEncode(<Object?>[
      <String, Object?>{'id': id, 'result': result},
    ]),
  );

  void exit(int code) => _exit.complete(code);

  @override
  Stream<List<int>> get stdout => _out.stream;

  @override
  Stream<List<int>> get stderr => _err.stream;

  @override
  IOSink get stdin => _in;

  @override
  Future<int> get exitCode => _exit.future;

  @override
  int get pid => 1;

  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) {
    if (!_exit.isCompleted) _exit.complete(-15);
    return true;
  }
}

final class _Sent implements StreamConsumer<List<int>> {
  _Sent(this.tool);

  final _Tool tool;

  @override
  Future<void> addStream(Stream<List<int>> stream) => stream
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .forEach((String line) {
        final [Object? message] = jsonDecode(line) as List<Object?>;
        tool.sent.add(message! as Map<String, Object?>);
      });

  @override
  Future<void> close() async {}
}

({FlutterRun run, _Tool tool, List<List<String>> started}) _run() {
  final tool = _Tool();
  final started = <List<String>>[];
  return (
    run: FlutterRun(
      projectRoot: '/game',
      device: 'macos',
      start: (List<String> arguments, String directory) async {
        started.add(<String>[directory, ...arguments]);
        return tool;
      },
    ),
    tool: tool,
    started: started,
  );
}

void main() {
  test('starts the tool in the project and follows it to running', () async {
    final it = _run();
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
    final it = _run();
    await it.run.start();
    it.tool.event('app.debugPort', <String, Object?>{
      'appId': 'a1',
      'wsUri': 'ws://x',
    });
    await pumpEventQueue();

    final reload = it.run.hotReload();
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
    final it = _run();
    await it.run.start();
    it.tool.event('app.debugPort', <String, Object?>{
      'appId': 'a1',
      'wsUri': 'ws://x',
    });
    await pumpEventQueue();

    final reload = it.run.hotReload();
    await pumpEventQueue();
    it.tool.exit(1);

    await expectLater(reload, throwsStateError);
    expect((it.run.state.value as PlayStopped).exitCode, 1);
  });

  test(
    'the console keeps the newest lines when a game logs every frame',
    () async {
      final it = _run();
      await it.run.start();
      for (var i = 0; i < FlutterRun.consoleLimit + 5; i++) {
        it.tool.say('line $i');
      }
      await pumpEventQueue();
      expect(it.run.console.value, hasLength(FlutterRun.consoleLimit));
      expect(it.run.console.value.first, 'line 5');
    },
  );

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

  testWidgets('the panel offers a reload only once the game is running', (
    WidgetTester tester,
  ) async {
    final it = _run();
    final timelines = <String>[];
    await it.run.start();
    await tester.pumpWidget(
      MaterialApp(
        home: PlayScreen(run: it.run, onTimeline: timelines.add),
      ),
    );

    IconButton button(String key) =>
        tester.widget<IconButton>(find.byKey(ValueKey<String>(key)));
    expect(button('play.reload').onPressed, isNull);
    expect(button('play.timeline').onPressed, isNull);

    it.tool.event('app.debugPort', <String, Object?>{
      'appId': 'a1',
      'wsUri': 'ws://game',
    });
    await tester.pump();
    await tester.pump();

    expect(find.text('Running, ws://game'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey<String>('play.reload')));
    await tester.pump();
    expect(it.tool.sent.single['method'], 'app.restart');

    await tester.tap(find.byKey(const ValueKey<String>('play.timeline')));
    expect(timelines, <String>['ws://game']);
  });
}
