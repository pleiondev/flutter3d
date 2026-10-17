/// `HR5` in a browser: a game attached to by its VM service, with no
/// process of the editor's own, read, reloaded, let go of and sent a level.
///
///     dart test test/attached_run_test.dart
library;

import 'package:flutter3d_editor_play/flutter3d_editor_play.dart';
import 'package:flutter3d_editor_play/testing.dart';
import 'package:test/test.dart';
import 'package:vm_service/vm_service.dart';

const String _document = '{"version": 1, "name": "yard", "fogDensity": 0.02}';

/// Lets the fake's replies and events cross the stream to the run.
Future<void> _settle() => Future<void>.delayed(Duration.zero);

Future<(FakeGame, AttachedRun)> _attached({
  Map<String, String>? registered,
}) async {
  final game = FakeGame(registered: registered ?? FakeGame.flutterTool());
  final run = fakeAttachedRun(game);
  await run.start();
  await _settle();
  return (game, run);
}

void main() {
  test('attaching is running, at the address given', () async {
    final (_, run) = await _attached();

    expect(
      run.state.value,
      isA<PlayRunning>().having(
        (it) => it.vmService,
        'vmService',
        'ws://game/ws',
      ),
    );
    expect(run.ownsTheGame, isFalse);
  });

  test('a line is what ends in a newline, not each write', () async {
    final (game, run) = await _attached();

    // What a real macOS run sends for `print('tick 1')`: the text, then the
    // newline on its own.
    game
      ..prints('flutter: tick 1')
      ..prints('\n')
      ..prints('flutter: half');
    await _settle();

    // Mutation: taking each write for a line puts an empty line after every
    // `print` and shows `half` before it is finished.
    expect(run.console.value, <String>['flutter: tick 1']);

    await game.exits();
    await _settle();
    expect(run.console.value.last, 'flutter: half');
  });

  test('the console is what the game prints and logs', () async {
    final (game, run) = await _attached();

    game
      ..prints('frame 1\nframe 2\n')
      ..logs('level loaded');
    await _settle();

    // Mutation: listening to `Stdout` alone drops what `log()` writes, and
    // a game that logs through `dart:developer` shows an empty console.
    expect(run.console.value, <String>['frame 1', 'frame 2', 'level loaded']);
  });

  test(
    'a hot reload is the flutter tool\'s, called in the main isolate',
    () async {
      final (game, run) = await _attached();

      expect(await run.hotSwap(), 'Swapped in the new code');

      // Mutation: calling the VM's own `reloadSources` instead of the name the
      // tool registered reaches a VM that cannot compile, which answers that
      // nothing changed while the game keeps its old code.
      final call = game.calls.last;
      expect(call['method'], 's0.reloadSources');
      expect(call['params'], containsPair('isolateId', FakeGame.isolateId));

      expect(await run.hotRestart(), 'Restarted with the new code');
      expect(game.calls.last['method'], 's0.hotRestart');
    },
  );

  test(
    'with no tool attached to the game, the reload says what to do',
    () async {
      final (game, run) = await _attached(registered: <String, String>{});
      final before = game.calls.length;

      final said = await run.hotSwap();

      // Mutation: falling back to the bare `reloadSources` would send a call
      // here and report success for a reload that did not happen.
      expect(game.calls, hasLength(before));
      expect(said, contains('flutter run'));
      expect(said, contains('flutter attach'));
      expect(run.console.value.last, said);
    },
  );

  test('a reload the tool refuses is said as refused', () async {
    final (game, run) = await _attached();
    game.toolAnswers['s0.reloadSources'] = RPCError(
      's0.reloadSources',
      RPCErrorKind.kInternalError.code,
      'Unable to reload sources',
    );

    final said = await run.hotSwap();

    expect(said, startsWith('the tool refused to swap new code into the game'));
    expect(said, contains('Unable to reload sources'));
  });

  test('stopping lets go of the game and does not end it', () async {
    final (game, run) = await _attached();

    await run.stop();

    // Mutation: an `exit` or `kill` on stop would end a game somebody else
    // started; the only calls are the attach's own.
    expect(game.calls.map((it) => it['method']).toSet(), <String>{
      'getVM',
      'streamListen',
    });
    expect(
      run.state.value,
      isA<PlayStopped>().having(
        (it) => it.reason,
        'reason',
        contains('keeps running'),
      ),
    );
    expect(await run.hotSwap(), isNull);
  });

  test('a game that exits is a run that stopped', () async {
    final (game, run) = await _attached();

    await game.exits();
    await _settle();

    expect(
      run.state.value,
      isA<PlayStopped>().having(
        (it) => it.reason,
        'reason',
        contains('closed'),
      ),
    );
  });

  test('an address with nothing behind it is a stop with a reason', () async {
    final run = AttachedRun(
      'http://127.0.0.1:1/',
      connect: (String _) async => throw StateError('connection refused'),
    );

    await run.start();

    expect(run.state.value, isA<PlayStopped>());
    expect(run.console.value.single, contains('connection refused'));
  });

  test('a saved level reaches the isolate that takes levels', () async {
    final game = FakeGame(extensions: <String>['ext.flutter3d.level.apply'])
      ..extensionAnswers['ext.flutter3d.level.apply'] = <String, Object?>{
        'type': '_extensionType',
        'swappedAt': 12,
        'diff': <String, Object?>{
          'simulation': <String>['brushes'],
        },
      };

    final answer = await pushLevel(
      'ws://game/ws',
      _document,
      connect: (String _) async => game.service,
    );

    expect(
      describeLevelApplied(answer),
      'the game replayed from step 12 with the new brushes',
    );
    final call = game.calls.last;
    expect(call['method'], 'ext.flutter3d.level.apply');
    expect(call['params'], containsPair('document', _document));
  });

  test('every spelling of the address is the same socket', () {
    for (final spelling in <String>[
      'http://127.0.0.1:8181/abc=/',
      'http://127.0.0.1:8181/abc=',
      'ws://127.0.0.1:8181/abc=/ws',
      ' ws://127.0.0.1:8181/abc=/ ',
    ]) {
      expect(vmServiceWebSocket(spelling), 'ws://127.0.0.1:8181/abc=/ws');
    }
    expect(vmServiceWebSocket('https://host/x/'), 'wss://host/x/ws');
  });
}
