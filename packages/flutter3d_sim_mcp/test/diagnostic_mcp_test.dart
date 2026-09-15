@TestOn('vm')
library;

/// `par-02`'s acceptance, read literally: an agent draws a headless frame,
/// reads a pixel back raw, reads the frame graph's own pass list, and can
/// name which pass is answerable for a wall that a broken normal map turned
/// dark — driven through the real MCP protocol, over a real socket, against
/// a real second process. See `pubspec.yaml` for why a socket and not
/// literal stdio.
///
///     flutter test test/diagnostic_mcp_test.dart
///
/// `@TestOn('vm')`: spawns a real process and opens a real socket.
///
/// **Moved here from `flutter3d_render_mcp` by the package-merge plan.**
/// The tools this drives are named `diag*` now rather than bare — `open`
/// and `frame` were already `flutter3d_sim_mcp`'s own before the two
/// packages merged, and an agent given one tool table cannot be offered two
/// tools with the same name. See `sim_server.dart`'s own doc comment for the
/// rest of what changed and what did not.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dart_mcp/client.dart';
import 'package:dart_mcp/stdio.dart';
import 'package:flutter3d_cpu/flutter3d_cpu.dart' show encodePng;
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

/// A one-pixel PNG, [rgb] over full alpha.
List<int> _texel(List<int> rgb) =>
    encodePng(Uint8List.fromList(<int>[...rgb, 255]), 1, 1);

/// A tiny level with two facing walls under one light: `good`'s normal map
/// is the engine's own neutral flat encoding, `broken`'s is solid black —
/// which `applyNormalMap`/`ApplyNormalMap` decode to a normal flipped away
/// from the surface (`texel * 2 - 1` over black is `(-1, -1, -1)`), so the
/// wall loses the light it would otherwise catch. Verified empirically
/// before this test was written: the same two materials, rendered once each
/// with nothing else different, read back 235 and 40 on an 8-bit channel —
/// not a NaN, a legitimate but wrong normal, which is the failure this
/// engine's guarded PBR path actually produces from a plausible authoring
/// mistake (a placeholder texture where a tangent-space map belongs).
Directory _writeWorkspace() {
  final workspace = Directory.systemTemp.createTempSync(
    'flutter3d_sim_mcp_diagnostic',
  );
  final textures = Directory('${workspace.path}/assets/textures')
    ..createSync(recursive: true);
  final levels = Directory('${workspace.path}/assets/levels')
    ..createSync(recursive: true);

  File('${textures.path}/good_normal.png').writeAsBytesSync(
    _texel(<int>[128, 128, 255]),
  );
  File('${textures.path}/broken_normal.png').writeAsBytesSync(
    _texel(<int>[0, 0, 0]),
  );

  final level = <String, Object?>{
    'version': 1,
    'name': 'par-02 probe',
    'materials': <String, Object?>{
      'good': <String, Object?>{
        'baseColor': <double>[0.8, 0.8, 0.8, 1.0],
        'roughness': 0.6,
        'normal': 'assets/textures/good_normal.png',
      },
      'broken': <String, Object?>{
        'baseColor': <double>[0.8, 0.8, 0.8, 1.0],
        'roughness': 0.6,
        'normal': 'assets/textures/broken_normal.png',
      },
    },
    'brushes': <Map<String, Object?>>[
      <String, Object?>{
        'at': <double>[-2.5, 1.0, 0.0],
        'size': <double>[3.0, 3.0, 0.2],
        'material': 'good',
      },
      <String, Object?>{
        'at': <double>[2.5, 1.0, 0.0],
        'size': <double>[3.0, 3.0, 0.2],
        'material': 'broken',
      },
    ],
    'lights': <Map<String, Object?>>[
      <String, Object?>{
        'type': 'point',
        'at': <double>[0.0, 1.0, 5.0],
        'color': <double>[1.0, 1.0, 1.0],
        'intensity': 12.0,
        'range': 20.0,
      },
    ],
    'entities': <Map<String, Object?>>[],
  };
  File('${levels.path}/probe.json').writeAsStringSync(jsonEncode(level));
  return workspace;
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

    workspace = _writeWorkspace();
  });

  tearDown(() async {
    await client.shutdown();
    await socket.close();
    process.kill();
    workspace.deleteSync(recursive: true);
  });

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
      if (content.isImage) png = base64Decode((content as ImageContent).data);
    }
    return (did: result.isError != true, says: says ?? '', png: png);
  }

  test('diagPixel before a frame is refused, not crashed', () async {
    final result = await call('diagPixel', <String, Object?>{'x': 0, 'y': 0});
    expect(result.did, isFalse);
    expect(result.says, contains('no frame drawn'));
  });

  test(
    'a broken normal map reads back darker than a correct one, and the '
    'answer names the pass responsible',
    () async {
      final opened = await call('diagOpen', <String, Object?>{
        'path': '${workspace.path}/assets/levels/probe.json',
      });
      expect(opened.did, isTrue, reason: opened.says);

      final drawn = await call('diagFrame', <String, Object?>{
        'atX': 0.0,
        'atY': 1.0,
        'atZ': 8.0,
        'aimX': 0.0,
        'aimY': 0.0,
        'aimZ': -1.0,
        'view': 'lit',
      });
      expect(drawn.did, isTrue, reason: drawn.says);
      expect(drawn.png, isNotNull);
      expect(
        drawn.says,
        contains('scene'),
        reason: 'the lit view names its own lighting pass unprompted',
      );

      // The PNG signature — proof this is actually a PNG.
      expect(
        drawn.png!.sublist(0, 8),
        <int>[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A],
      );

      // The brightest pixel in each half of the frame is that half's own
      // wall — found by scanning rather than assumed from hand projection,
      // since the exact pixel a world position lands on is the renderer's
      // to decide, not this test's. Read through `diagPixel` itself,
      // sampling a grid and keeping the brightest cell each side of the
      // frame's own midline.
      const width = 320, height = 200;
      double bestLeft = -1, bestRight = -1;
      var bestRightXY = (0, 0);
      for (var y = 20; y < height; y += 20) {
        for (var x = 10; x < width; x += 10) {
          final read = await call('diagPixel', <String, Object?>{
            'x': x,
            'y': y,
          });
          expect(read.did, isTrue, reason: read.says);
          final words = jsonDecode(read.says) as Map<String, Object?>;
          final rgba = (words['rgba']! as List<Object?>).cast<num>();
          final luma = rgba[0] + rgba[1] + rgba[2];
          if (x < width ~/ 2 && luma > bestLeft) {
            bestLeft = luma.toDouble();
          }
          if (x >= width ~/ 2 && luma > bestRight) {
            bestRight = luma.toDouble();
            bestRightXY = (x, y);
          }
        }
      }
      expect(
        bestLeft,
        greaterThan(0.3),
        reason: 'the good wall (world x = -2.5, left of screen) should be '
            'clearly lit somewhere in the left half',
      );
      expect(
        bestRight,
        lessThan(bestLeft * 0.6),
        reason: 'the broken wall (world x = +2.5, right of screen) should '
            'read back markedly darker than the good one, from the same '
            'light, the same material otherwise, and nothing different but '
            'the normal map',
      );

      final passes = await call('diagPasses');
      expect(passes.did, isTrue);
      final passList = (jsonDecode(passes.says) as List<Object?>)
          .cast<Map<String, Object?>>();
      expect(
        passList.any((p) => p['name'] == 'scene' && p['active'] == true),
        isTrue,
        reason: 'the pass `diagPixel` already named should actually be in '
            'the graph this frame ran',
      );

      // What an agent reasons from: `diagPixel` at the dark spot names the
      // same pass `diagPasses` says ran — that is the naming this
      // acceptance asks for, stated as data rather than as a free-text
      // guess.
      final darkPixel = await call('diagPixel', <String, Object?>{
        'x': bestRightXY.$1,
        'y': bestRightXY.$2,
      });
      expect(darkPixel.says, contains('"pass"'));
      expect(darkPixel.says, contains('scene'));
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );
}
