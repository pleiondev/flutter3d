/// `mcp-16d`'s own acceptance, over the real socket
/// `startMcpServer`/`mcp_bootstrap_io.dart` actually starts: a headless
/// document server (no `uiActions`) lists no `ui.*` tool, and a GUI-mode one
/// (a live [UiActions] handed in, the way `screen/files.dart` hands in a
/// [ModelerUiActions]) lists every one of them. `mcp_bootstrap_test.dart` already
/// covers the plain document server; this is the same shape, once for each
/// side of that difference.
///
///     flutter test test/mcp_ui_tools_test.dart
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter3d_model_core/flutter3d_model_core.dart';
import 'package:flutter3d_modeler/src/mcp_bootstrap_io.dart';
import 'package:flutter3d_modeler/src/mcp_ui_actions.dart';
import 'package:flutter_test/flutter_test.dart';

/// Answers every call the same way, without touching anything — this test
/// asks only whether the tools are offered and reachable, not what a
/// real screen does with one; `modeler_ui_actions_test.dart` covers that.
final class _NoopUiActions implements UiActions {
  const _NoopUiActions();

  @override
  UiAnswer setMode(String mode) => (did: true, says: 'ok');

  @override
  UiAnswer setSubmode(String submode) => (did: true, says: 'ok');

  @override
  UiAnswer setTool(String? id) => (did: true, says: 'ok');

  @override
  UiAnswer standardView(String view) => (did: true, says: 'ok');

  @override
  UiAnswer frameSubject() => (did: true, says: 'ok');

  @override
  UiAnswer openDialog(String dialog) => (did: true, says: 'ok');

  @override
  UiAnswer say(String text) => (did: true, says: 'ok');

  @override
  Future<UiPicture> screenshot() async =>
      (did: false, says: 'no window here', png: null);

  @override
  UiAnswer runCommand(String id) => (did: true, says: 'ran $id');

  @override
  UiAnswer console({DateTime? since}) => (did: true, says: 'nothing said');

  @override
  UiAnswer playStart(String template) => (did: true, says: 'ok');

  @override
  UiAnswer playReload() => (did: true, says: 'ok');

  @override
  UiAnswer playStop() => (did: true, says: 'ok');

  @override
  UiAnswer playConsole() => (did: true, says: 'ok');

  @override
  Future<UiPicture> playScreenshot() async =>
      (did: false, says: 'no window here', png: null);

  @override
  List<({String id, String label, String mode})> commands() =>
      const <({String id, String label, String mode})>[
        (id: 'object.duplicate', label: 'Duplicate', mode: 'object'),
      ];
}

const List<String> _uiToolNames = <String>[
  'ui.setMode',
  'ui.setSubmode',
  'ui.setTool',
  'ui.standardView',
  'ui.frameSubject',
  'ui.openDialog',
  'ui.say',
  // `ux-44`: the window as a picture — what the person sees, which
  // `render` cannot show because it draws the model without the interface.
  'ui.screenshot',
  // `ux-25`: the palette's own list and door, offered to an agent under the
  // name the row gives it rather than a `ui.` one — it runs a command rather
  // than moving the interface.
  'run_command',
  // `ux-52`: Play, driven from outside the route it runs in — five names
  // rather than one verb argument, so a tool list says what it can do.
  'play.start',
  'play.reload',
  'play.stop',
  'play.console',
  'play.screenshot',
  // `ux-26`: the same reasoning — it reads the session rather than moving
  // anything, and the row names it.
  'get_console',
];

void main() {
  late Directory workspace;

  setUp(() {
    workspace = Directory.systemTemp.createTempSync('flutter3d_modeler_mcp_ui');
  });

  tearDown(() async {
    await stopMcpServer();
    if (workspace.existsSync()) workspace.deleteSync(recursive: true);
  });

  test(
    'no uiActions: not one ui.* tool is listed — the headless shape',
    () async {
      await startMcpServer(
        history: ModelHistory(const ModelProject()),
        port: 0,
        sessionDirectory: workspace,
      );

      final names = await _listedToolNames(workspace);
      expect(names.where((name) => name.startsWith('ui.')), isEmpty);
    },
  );

  test('a live uiActions: every screen tool is listed', () async {
    await startMcpServer(
      history: ModelHistory(const ModelProject()),
      port: 0,
      uiActions: const _NoopUiActions(),
      sessionDirectory: workspace,
    );

    final names = await _listedToolNames(workspace);
    expect(
      names
          .where(
            (String name) =>
                name.startsWith('ui.') ||
                name.startsWith('play.') ||
                name == 'run_command' ||
                name == 'get_console',
          )
          .toSet(),
      _uiToolNames.toSet(),
    );
  });

  test('ux-25: run_command with no id answers with the catalogue', () async {
    await startMcpServer(
      history: ModelHistory(const ModelProject()),
      port: 0,
      uiActions: const _NoopUiActions(),
      sessionDirectory: workspace,
    );

    final session = await _session(workspace);
    await _initialize(session);
    final called = await _call(session, <String, Object?>{
      'jsonrpc': '2.0',
      'id': 3,
      'method': 'tools/call',
      'params': <String, Object?>{
        'name': 'run_command',
        'arguments': <String, Object?>{},
      },
    });

    // Mutation: refuse without an id. An agent that has never seen this
    // editor then has no way to find out what it can ask for by name, which
    // is the half of "one table for the person and the agent" that faces the
    // agent.
    final result = called['result']! as Map<String, Object?>;
    expect(result['isError'], isNot(true));
    expect(json.encode(result), contains('object.duplicate'));
  });

  test('ui.setMode is callable over the real socket', () async {
    await startMcpServer(
      history: ModelHistory(const ModelProject()),
      port: 0,
      uiActions: const _NoopUiActions(),
      sessionDirectory: workspace,
    );

    final session = await _session(workspace);
    await _initialize(session);
    final called = await _call(session, <String, Object?>{
      'jsonrpc': '2.0',
      'id': 3,
      'method': 'tools/call',
      'params': <String, Object?>{
        'name': 'ui.setMode',
        'arguments': <String, Object?>{'mode': 'animation'},
      },
    });
    final result = called['result']! as Map<String, Object?>;
    expect(result['isError'], isNot(true));
  });
}

Future<({int port, String token})> _session(Directory workspace) async {
  final written =
      json.decode(File('${workspace.path}/mcp-session.json').readAsStringSync())
          as Map<String, Object?>;
  return (port: written['port']! as int, token: written['token']! as String);
}

Future<Map<String, Object?>> _call(
  ({int port, String token}) session,
  Object? body,
) async {
  final httpClient = HttpClient();
  try {
    final request = await httpClient.postUrl(
      Uri.parse('http://127.0.0.1:${session.port}/mcp?token=${session.token}'),
    );
    request.headers.contentType = ContentType.json;
    request.write(json.encode(body));
    final response = await request.close();
    final text = await response.transform(utf8.decoder).join();
    return text.isEmpty
        ? const <String, Object?>{}
        : json.decode(text) as Map<String, Object?>;
  } finally {
    httpClient.close(force: true);
  }
}

Future<void> _initialize(({int port, String token}) session) async {
  await _call(session, <String, Object?>{
    'jsonrpc': '2.0',
    'id': 1,
    'method': 'initialize',
    'params': <String, Object?>{
      'protocolVersion': '2024-11-05',
      'capabilities': <String, Object?>{},
      'clientInfo': <String, Object?>{
        'name': 'mcp_ui_tools_test',
        'version': '0.0.1',
      },
    },
  });
  await _call(session, <String, Object?>{
    'jsonrpc': '2.0',
    'method': 'notifications/initialized',
  });
}

Future<List<String>> _listedToolNames(Directory workspace) async {
  final session = await _session(workspace);
  await _initialize(session);
  final listed = await _call(session, <String, Object?>{
    'jsonrpc': '2.0',
    'id': 2,
    'method': 'tools/list',
  });
  final tools =
      (listed['result']! as Map<String, Object?>)['tools']! as List<Object?>;
  return <String>[
    for (final tool in tools)
      (tool! as Map<String, Object?>)['name']! as String,
  ];
}
