@TestOn('vm')
library;

/// `ai-00`'s acceptance, read literally: an agent opens the crypt, steps it
/// forward, reads back words rather than pixels, and hands over a run that
/// opens like any other — driven through the real MCP protocol, over a real
/// socket, against a real second process. See `pubspec.yaml` for why a
/// socket and not literal stdio.
///
///     dart test test/sim_mcp_test.dart
///
/// `@TestOn('vm')`: spawns a real process and opens a real socket.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dart_mcp/client.dart';
import 'package:dart_mcp/stdio.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:flutter3d_sim_mcp/flutter3d_sim_mcp.dart';
import 'package:test/test.dart';

Future<({Process process, int port})> _startServer() async {
  final process = await Process.start(
    'flutter',
    <String>[
      'test',
      '--reporter=silent',
      'test/fixtures/sim_mcp_server.dart',
    ],
    workingDirectory: Directory.current.path,
  );
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
  final port = await portFound.future.timeout(
    const Duration(seconds: 60),
    onTimeout: () {
      process.kill();
      throw StateError('the server never printed the port it bound to');
    },
  );
  await subscription.cancel();
  return (process: process, port: port);
}

void main() {
  late Process process;
  late Socket socket;
  late MCPClient client;
  late ServerConnection connection;
  late Directory workspace;

  setUp(() async {
    final server = await _startServer();
    process = server.process;
    socket = await Socket.connect(InternetAddress.loopbackIPv4, server.port);

    client = MCPClient(Implementation(name: 'the suite', version: simMcpVersion));
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

    workspace = Directory.systemTemp.createTempSync('flutter3d_sim_mcp');
  });

  tearDown(() async {
    await client.shutdown();
    await socket.close();
    process.kill();
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

  test(
    'the eleven tools an agent is offered are the ones it can call — six '
    'for a level played blind, five for a frame diagnosed independently of '
    'it, folded in by the package-merge plan',
    () async {
      final offered = await connection.listTools(ListToolsRequest());
      final names = offered.tools.map((t) => t.name).toSet();
      expect(names, <String>{
        'open',
        'step',
        'snapshot',
        'digest',
        'writeRun',
        'frame',
        'diagOpen',
        'diagFrame',
        'diagPixel',
        'diagPasses',
        'diagScanNaN',
      });
    },
  );

  test('a run before opening a level is refused, not crashed', () async {
    final result = await call('step', <String, Object?>{'steps': 1});
    expect(result.did, isFalse);
    expect(result.says, contains('no level open'));
  });

  test(
    'an agent walks the crypt from words alone, and the run it hands over '
    'opens like any other',
    () async {
      final opened = await call('open', <String, Object?>{
        'path': '../../apps/flutter3d_demo_dungeon/assets/levels/crypt.json',
      });
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
      expect(
        frame.png!.sublist(0, 8),
        <int>[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A],
      );

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
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );
}
