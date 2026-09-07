/// Three torches, placed by an agent, and the file that comes out.
///
/// **A whole session, driven through the real protocol.** The client and the
/// server here are the ones a host would run; what is faked is only the pipe
/// between them, a pair of in-memory streams instead of a process's stdin and
/// stdout. So this covers the parts that unit tests of a session cannot reach:
/// that every tool is registered under the name the table claims, that the
/// schemas accept the arguments the tools' own descriptions tell an agent to
/// send, and that a refusal comes back as a result the model can read rather
/// than as a dead connection.
///
/// **And it diffs text, which is the point.** Byte stability was already
/// settled — the document is written through `JsonEncoder.withIndent('  ')` and
/// every coordinate is snapped to a quarter of a metre before it is written — so
/// a fixture is a fair thing to compare against, and a change that moves one
/// number moves one line of a diff a person can read.
library;

import 'dart:io';

import 'package:dart_mcp/client.dart';
import 'package:flutter3d_editor_mcp/flutter3d_editor_mcp.dart';
import 'package:stream_channel/stream_channel.dart';
import 'package:test/test.dart';

void main() {
  late Directory workspace;
  late MCPClient client;
  late ServerConnection connection;
  late String started;

  /// A copy of the template, in a directory of its own.
  ///
  /// A copy because the scenario saves, and the second half of what it proves
  /// is that saving over the original is refused — a test that could write to
  /// `apps/` would be a test that fails once and then passes for ever.
  setUp(() async {
    workspace = Directory.systemTemp.createTempSync('flutter3d_editor_mcp');
    started = '${workspace.path}/level.first.json';
    File(started).writeAsStringSync(
      File('test/fixtures/shooter.first.json').readAsStringSync(),
    );

    final pipe = StreamChannelController<String>(sync: true);
    EditorMcpServer(pipe.local, session: EditorSession.open(started));

    client = MCPClient(
      Implementation(name: 'the suite', version: editorMcpVersion),
    );
    connection = client.connectServer(pipe.foreign);
    final ready = await connection.initialize(
      InitializeRequest(
        protocolVersion: ProtocolVersion.latestSupported,
        capabilities: client.capabilities,
        clientInfo: client.implementation,
      ),
    );
    expect(ready.capabilities.tools, isNotNull);
    connection.notifyInitialized();
  });

  tearDown(() async {
    await client.shutdown();
    workspace.deleteSync(recursive: true);
  });

  /// One tool call, and the sentence it answered with.
  Future<({bool did, String says})> call(
    String name, [
    Map<String, Object?> arguments = const <String, Object?>{},
  ]) async {
    final result = await connection.callTool(
      CallToolRequest(name: name, arguments: arguments),
    );
    final content = result.content.single;
    expect(content.isText, isTrue, reason: '$name answered with $content');
    return (did: result.isError != true, says: (content as TextContent).text);
  }

  test('the starting document is still the template it was copied from', () {
    // **A copy, and a copy that is checked.** The scenario needs a level that
    // says it was generated, because half of what it proves is that saving
    // over one is refused — and the honest source for that is the shooter
    // template the editor scaffolds a project from. It cannot be read from
    // there: a package that reached into `apps/` for a fixture would be a
    // package whose suite only runs inside this checkout. So it is copied, and
    // `tool/make_templates.py` regenerates the original in CI, which is
    // precisely the arrangement that drifts silently. This is the line that
    // makes the drift loud.
    final template = File(
      '../../apps/flutter3d_editor/assets/templates/shooter/level.first.json',
    );
    if (!template.existsSync()) {
      markTestSkipped(
        'outside the checkout there is no application to compare against',
      );
      return;
    }
    expect(
      File('test/fixtures/shooter.first.json').readAsStringSync(),
      template.readAsStringSync(),
      reason:
          'the shooter template moved and this copy of it did not. Copy the '
          'template over test/fixtures/shooter.first.json and regenerate '
          'test/fixtures/three_torches.json with it',
    );
  });

  test('the tools an agent is offered are the ones it can call', () async {
    final offered = await connection.listTools(ListToolsRequest());
    expect(
      offered.tools.map((Tool it) => it.name),
      editorTools.map((EditorTool it) => it.name),
      reason: 'tools/list and the table this server was built from disagree',
    );

    // Every one of them answers something, including the ones that refuse.
    // A tool registered under a name nothing implements answers "no tool
    // registered with the name …", which is a sentence this would catch.
    for (final tool in offered.tools) {
      expect(tool.description, isNotEmpty, reason: '${tool.name} says nothing');
    }
  });

  test('a level nobody has touched has nothing wrong with it', () async {
    expect((await call('validate')).says, 'no issues');
  });

  test('the listing names what select takes', () async {
    final listing = await call('list');
    expect(listing.did, isTrue);
    expect(listing.says, contains('brush 0 · floor · at 0, -0.5, 0 · 16×1×16'));
    expect(listing.says, contains('light 0 · point · at 0, 3.2, 0'));
    expect(listing.says, contains('entity 1 · torch · at -7.7, 2.6, 0'));
    expect(listing.says, contains('nothing selected — call select'));

    final picked = await call('select', <String, Object?>{
      'kind': 'entity',
      'index': 1,
    });
    expect(picked.did, isTrue);
    expect(picked.says, startsWith('entity 1 · torch'));
  });

  test(
    'an index the level does not have is refused rather than ignored',
    () async {
      final missed = await call('select', <String, Object?>{
        'kind': 'brush',
        'index': 40,
      });
      expect(missed.did, isFalse);
      expect(missed.says, contains('there is no brush 40'));
    },
  );

  test('a generated document is not written over', () async {
    // **Half the value of this file.** The template says `generatedBy:
    // tool/make_templates.py`, and `tool/ci.sh` regenerates it and diffs — so a
    // server that wrote back over one would produce work that looks saved right
    // up until the next CI run throws it away, with nothing having said so.
    final refused = await call('save');
    expect(refused.did, isFalse);
    expect(refused.says, contains('tool/make_templates.py'));
    expect(refused.says, contains('will not be overwritten'));

    // The refusal changed nothing on the disk, which is the part that matters:
    // "will not be overwritten" printed after a write is worse than silence.
    expect(
      File(started).readAsStringSync(),
      File('test/fixtures/shooter.first.json').readAsStringSync(),
    );
  });

  test('three torches, and the document that comes out', () async {
    // Where a person would put them: high on three of the four walls, on the
    // grid, so the numbers written down are the numbers asked for.
    const at = <List<double>>[
      <double>[7.75, 2.5, 0.0],
      <double>[0.0, 2.5, -8.0],
      <double>[0.0, 2.5, 8.0],
    ];
    for (final where in at) {
      final placed = await call('place', <String, Object?>{
        'kind': 'entity',
        'what': 'torch',
        'at': where,
      });
      expect(placed.did, isTrue, reason: placed.says);
      // Placed by copying the last one of that type, so each carries the
      // template torch's facing rather than a zero this package invented.
      expect(placed.says, startsWith('place a torch at'));
    }

    expect((await call('validate')).says, 'no issues');

    final saved = await call('save', <String, Object?>{
      'path': '${workspace.path}/three_torches.json',
    });
    expect(saved.did, isTrue, reason: saved.says);

    expect(
      File('${workspace.path}/three_torches.json').readAsStringSync(),
      File('test/fixtures/three_torches.json').readAsStringSync(),
      reason:
          'the document written after three place calls is not the one in '
          'test/fixtures. If the change was meant, copy the new file over the '
          'fixture and read the diff before you do',
    );
  });

  test('undo puts back what the last call did, by name', () async {
    await call('place', <String, Object?>{
      'kind': 'entity',
      'what': 'torch',
      'at': <double>[0.0, 2.5, 8.0],
    });
    final back = await call('undo');
    expect(back.did, isTrue);
    expect(back.says, contains('place a torch at 0, 2.5, 8'));
    expect((await call('list')).says, isNot(contains('entity 4')));

    final again = await call('redo');
    expect(again.did, isTrue);
    expect((await call('list')).says, contains('entity 4 · torch'));
  });

  test('the server says why it cannot draw', () async {
    final refused = await call('screenshot');
    expect(refused.did, isFalse);
    expect(refused.says, contains('cannot draw'));
    expect(refused.says, contains('Flutter'));
  });
}
