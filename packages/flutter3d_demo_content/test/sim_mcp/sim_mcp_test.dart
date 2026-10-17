@TestOn('vm')
// Three minutes: the server's start runs in `setUpAll`, under this. It said
// its port in 25 s alone and took longer than 60 s under a full CI run.
@Timeout(Duration(minutes: 3))
library;

/// `ai-00`'s acceptance, read literally: an agent opens the crypt, steps it
/// forward, reads back words rather than pixels, and hands over a run that
/// opens like any other — driven through the real MCP protocol, over a real
/// socket, against a real second process. See `pubspec.yaml` for why a
/// socket and not literal stdio.
///
///     dart test test/sim_mcp/sim_mcp_test.dart
///
/// `@TestOn('vm')`: spawns a real process and opens a real socket.
///
/// **One server for the file, a connection for each test.** Starting the
/// server is a `flutter test` of its own, and nearly all of that is the
/// compile of every genre it can play: 42 of the 60 seconds it took to say
/// its port under load. Started once a test, five of those put the file
/// past five minutes and two of its tests past their minute; started once,
/// the file ran in 34 seconds under the same load. Each connection is a
/// session of its own on the server (`sim_mcp_server.dart`), so a test
/// still starts from a server that has opened nothing.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dart_mcp/client.dart';
import 'package:dart_mcp/stdio.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:flutter3d_sim_mcp/flutter3d_sim_mcp.dart';
import 'package:test/test.dart';

/// The crypt, by its absolute path: a relative one is read from the
/// server's root, the repository, not from this package.
final String _crypt = File(
  '../../apps/flutter3d_demo_dungeon/assets/levels/crypt.json',
).resolveSymbolicLinksSync();

/// Starts the server and answers its port. Called from `setUpAll`, so the
/// tear-down it registers kills the server after the file's last test, and
/// also when the start itself is what failed.
Future<int> _startServer() async {
  final process = await Process.start('flutter', <String>[
    'test',
    // Resolved already: this suite is running.
    '--no-pub',
    '--reporter=silent',
    'test/sim_mcp/fixtures/sim_mcp_server.dart',
  ], workingDirectory: Directory.current.path);
  addTearDown(process.kill);
  final portFound = Completer<int>();
  final subscription = process.stdout
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .listen((line) {
        final match = RegExp(
          r'flutter3d_sim_mcp listening on (\d+)',
        ).firstMatch(line);
        if (match != null && !portFound.isCompleted) {
          portFound.complete(int.parse(match.group(1)!));
        }
      });
  // **Ready when it says its port, failed when it exits first.** A clock of
  // 60 seconds here ran out under a full CI run, where the compile alone
  // outlasted it; how long the start may take is the file's timeout.
  final int port;
  try {
    port = await Future.any(<Future<int>>[
      portFound.future,
      process.exitCode.then(
        (code) => throw StateError(
          'the server exited with $code before it printed the port it '
          'bound to',
        ),
      ),
    ]);
  } finally {
    await subscription.cancel();
  }
  return port;
}

void main() {
  late int port;
  late Socket socket;
  late MCPClient client;
  late ServerConnection connection;
  late Directory workspace;

  setUpAll(() async {
    port = await _startServer();
  });

  setUp(() async {
    socket = await Socket.connect(InternetAddress.loopbackIPv4, port);

    client = MCPClient(
      Implementation(name: 'the suite', version: simMcpVersion),
    );
    connection = client.connectServer(
      stdioChannel(input: socket, output: socket),
    );
    final ready = await connection.initialize(
      InitializeRequest(
        protocolVersion: ProtocolVersion.latestSupported,
        capabilities: client.capabilities,
        clientInfo: client.implementation,
      ),
    );
    expect(ready.capabilities.tools, isNotNull);
    connection.notifyInitialized();

    // Inside the server's root, the repository, as every path it is handed
    // must be.
    workspace = (Directory(
      '.dart_tool',
    )..createSync()).absolute.createTempSync('flutter3d_sim_mcp');
  });

  tearDown(() async {
    await client.shutdown();
    await socket.close();
    workspace.deleteSync(recursive: true);
  });

  /// One tool call, its text, and — for `frame` — the image bytes.
  Future<({bool did, String says, List<int>? png})> call(
    String name, [
    Map<String, Object?> arguments = const <String, Object?>{},
  ]) async {
    final result = await connection.callTool(
      CallToolRequest(name: name, arguments: arguments),
    );
    String? says;
    List<int>? png;
    for (final content in result.content) {
      if (content.isText) says = (content as TextContent).text;
      if (content.isImage) {
        png = base64Decode((content as ImageContent).data);
      }
    }
    return (did: result.isError != true, says: says ?? '', png: png);
  }

  test('the nine tools an agent is offered are the ones it can call', () async {
    final offered = await connection.listTools(ListToolsRequest());
    final names = offered.tools.map((t) => t.name).toSet();
    // Each published as `area.verb`, and the schema every server answers.
    // The written names still answer until 2.0, but an agent is not offered
    // them: each would be a second copy of a tool it already has.
    expect(names, <String>{
      'level.open',
      'run.step',
      'state.snapshot',
      'run.digest',
      'run.write',
      'view.frame',
      'run.expect',
      'run.verify',
      'run.bisect',
      'flutter3d.schema',
    });
    // Mutation: list the aliases again, or drop them from the wire.
    expect((await call('digest')).says, (await call('run.digest')).says);
  });

  test('a run before opening a level is refused, not crashed', () async {
    final result = await call('step', <String, Object?>{'steps': 1});
    expect(result.did, isFalse);
    expect(result.says, contains('no level open'));
  });

  test('an agent walks the crypt from words alone, and the run it hands over '
      'opens like any other', () async {
    final opened = await call('open', <String, Object?>{'path': _crypt});
    expect(opened.did, isTrue, reason: opened.says);
    expect(opened.says, contains('player at'));

    final before = await call('snapshot');
    expect(before.did, isTrue);
    final beforeWords = jsonDecode(before.says) as Map<String, Object?>;
    expect(beforeWords['player'], isNotNull);
    expect(beforeWords['actors'], isA<List<Object?>>());

    // Sixty steps forward, so at least one checkpoint (every 25) is taken.
    final stepped = await call('step', <String, Object?>{
      'steps': 60,
      'moveY': 1.0,
    });
    expect(stepped.did, isTrue);
    expect(stepped.says, contains('stepped to 60'));

    final digest = await call('digest');
    expect(digest.did, isTrue);
    expect(
      digest.says,
      isNot(contains('no checkpoint')),
      reason: '60 steps should have crossed the first checkpoint at 25',
    );

    final frame = await call('frame');
    expect(frame.did, isTrue, reason: frame.says);
    expect(
      frame.png,
      isNotNull,
      reason: 'a frame answer with no image content is not a frame',
    );
    // The PNG signature — proof this is actually a PNG and not raw bytes
    // wearing the mime type.
    expect(frame.png!.sublist(0, 8), <int>[
      0x89,
      0x50,
      0x4E,
      0x47,
      0x0D,
      0x0A,
      0x1A,
      0x0A,
    ]);

    final runPath = '${workspace.path}/agent.f3drun';
    final written = await call('writeRun', <String, Object?>{'path': runPath});
    expect(written.did, isTrue, reason: written.says);

    // Opens like any other run — read back exactly the way
    // `apps/flutter3d_editor`'s own timeline would.
    final demo = Demo.fromJson(
      jsonDecode(File(runPath).readAsStringSync()) as Map<String, Object?>,
    );
    expect(demo.tape.steps, 60);
    expect(demo.checkpoints.steps, isNotEmpty);
  });

  test(
    'an agent bisects two runs to the step and the field they part on',
    () async {
      Future<String> run(String name, List<Map<String, Object?>> legs) async {
        expect(
          (await call('open', <String, Object?>{'path': _crypt})).did,
          isTrue,
        );
        for (final leg in legs) {
          expect((await call('step', leg)).did, isTrue);
        }
        final path = '${workspace.path}/$name.f3drun';
        expect(
          (await call('writeRun', <String, Object?>{'path': path})).did,
          isTrue,
        );
        return path;
      }

      final straight = await run('straight', <Map<String, Object?>>[
        <String, Object?>{'steps': 50, 'moveY': 1.0},
      ]);
      final aside = await run('aside', <Map<String, Object?>>[
        <String, Object?>{'steps': 30, 'moveY': 1.0},
        <String, Object?>{'steps': 20, 'moveX': 1.0},
      ]);
      final found = await call('bisect', <String, Object?>{
        'a': straight,
        'b': aside,
      });
      expect(found.did, isTrue, reason: found.says);
      expect(found.says, contains('part at step 31'));
      expect(found.says, contains('step 30 had different input'));
    },
  );

  test(
    'an agent bisects two runs to the step and the component they part on',
    () async {
      // P12's last line, over the wire from a cold session: two runs of the
      // crypt, one of which pulls the trigger on the monster ahead, bisected
      // to the step and the entity component where they first differ.
      Future<String> run(String name, {required bool fire}) async {
        expect(
          (await call('open', <String, Object?>{'path': _crypt})).did,
          isTrue,
        );
        expect(
          (await call('step', <String, Object?>{
            'steps': 20,
            'moveY': 1.0,
          })).did,
          isTrue,
        );
        expect(
          (await call('step', <String, Object?>{
            'steps': 20,
            'moveY': 1.0,
            'fire': fire,
          })).did,
          isTrue,
        );
        final path = '${workspace.path}/$name.f3drun';
        expect(
          (await call('writeRun', <String, Object?>{'path': path})).did,
          isTrue,
        );
        return path;
      }

      final walked = await run('walked', fire: false);
      final fired = await run('fired', fire: true);
      final found = await call('bisect', <String, Object?>{
        'a': walked,
        'b': fired,
        'entities': <String, Object?>{
          'ecs': <String>['entities'],
        },
      });
      expect(found.did, isTrue, reason: found.says);
      expect(found.says, contains('part at step 21'));
      expect(found.says, contains('step 20 had different input'));
      expect(found.says, contains('The first component that differs is 0.'));
      expect(found.says, contains('0.vitality'));

      // A layout that names both shapes is refused, not guessed at.
      final both = await call('bisect', <String, Object?>{
        'a': walked,
        'b': fired,
        'entities': <String, Object?>{
          'ecs': <String>['entities'],
          'rows': 'actors',
        },
      });
      expect(both.did, isFalse);
      expect(both.says, contains('one of the two'));
    },
  );
}
