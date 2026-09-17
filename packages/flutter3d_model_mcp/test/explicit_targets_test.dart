/// `ux-20`'s own acceptance: a command can say what it acts on, a batch is
/// all or nothing, and a recipe puts the selection back.
///
/// **The selection was a hidden argument, and this row makes it optional.**
/// Every mesh command read `history.selection`, so driving the editor from
/// outside meant two calls per operation with a piece of state between them
/// that neither call mentioned — and the review found what that costs: a
/// recipe moved the selection halfway through and the next edit landed
/// somewhere nobody asked for.
///
///     dart test test/explicit_targets_test.dart
library;

import 'dart:io';

import 'package:dart_mcp/client.dart';
import 'package:flutter3d_model_core/flutter3d_model_core.dart';
import 'package:flutter3d_model_mcp/flutter3d_model_mcp.dart';
import 'package:stream_channel/stream_channel.dart';
import 'package:test/test.dart';

void main() {
  late Directory workspace;
  late ModelSession session;
  late MCPClient client;
  late ServerConnection connection;

  setUp(() async {
    workspace = Directory.systemTemp.createTempSync(
      'flutter3d_model_mcp_explicit_targets',
    );
    session = ModelSession.open('${workspace.path}/scene.f3dproj');
    final pipe = StreamChannelController<String>(sync: true);
    ModelMcpServer(pipe.local, session: session);
    client = MCPClient(
      Implementation(name: 'the suite', version: modelMcpVersion),
    );
    connection = client.connectServer(pipe.foreign);
    await connection.initialize(
      InitializeRequest(
        protocolVersion: ProtocolVersion.latestSupported,
        capabilities: client.capabilities,
        clientInfo: client.implementation,
      ),
    );
    connection.notifyInitialized();
  });

  tearDown(() async {
    await client.shutdown();
    workspace.deleteSync(recursive: true);
  });

  Future<CallToolResult> call(
    String name, [
    Map<String, Object?> arguments = const <String, Object?>{},
  ]) => connection.callTool(CallToolRequest(name: name, arguments: arguments));

  String saidBy(CallToolResult result) =>
      (result.content.single as TextContent).text;

  /// A cube with topology, and nothing selected.
  Future<void> aCube() async {
    await call('addPrimitive', <String, Object?>{'kind': 'box'});
    await call('bakeToMesh', <String, Object?>{'id': 1});
    await call('selectNone');
    session.history.selection = const ProjectSelection();
  }

  test('extrude with an explicit face works with an empty selection, and '
      'leaves it empty', () async {
    await aCube();
    expect(session.history.selection.isEmpty, isTrue);
    final int facesBefore =
        (session.project[1]!.geometry as EditedGeometry).mesh.faceCount;

    final CallToolResult extruded = await call('extrude', <String, Object?>{
      'object': 1,
      'faces': <int>[0],
      'distance': 0.4,
    });
    expect(extruded.isError, isNot(true), reason: saidBy(extruded));

    // It really extruded.
    expect(
      (session.project[1]!.geometry as EditedGeometry).mesh.faceCount,
      greaterThan(facesBefore),
    );

    // Mutation: leave the selection where the command put it. A call that
    // names its own target is not asking to move somebody's cursor — and the
    // person at the window has one.
    expect(session.history.selection.isEmpty, isTrue);

    // The ids are not lost with it: what the command selected while it ran is
    // what the answer reports.
    final Map<String, Object?> selection =
        extruded.structuredContent!['selection']! as Map<String, Object?>;
    expect(selection['mode'], 'mesh');
    expect(selection['elements']! as List<Object?>, isNotEmpty);
  });

  test('a target on an object-level command names objects', () async {
    await call('addPrimitive', <String, Object?>{'kind': 'box'});
    await call('addPrimitive', <String, Object?>{'kind': 'sphere'});
    await call('selectNone');

    final CallToolResult moved = await call('moveBy', <String, Object?>{
      'ids': <int>[1],
      'by': <double>[0, 3, 0],
    });
    expect(moved.isError, isNot(true), reason: saidBy(moved));

    expect(session.project[1]!.transform.storage[13], closeTo(3.0, 1e-6));
    expect(session.project[2]!.transform.storage[13], closeTo(0.0, 1e-6));
    expect(session.history.selection.objects, isEmpty);
  });

  test('naming an object with no level says so rather than guessing', () {
    // Reached in Dart rather than over the protocol, because the tools
    // themselves cannot ask this: `faces`/`edges`/`vertices` carry the level
    // with the ids, and `ux-43` took the second spelling away. A caller that
    // aims at an object's mesh without saying at what grain still gets a
    // sentence rather than a guess.
    final Answer refused = session.runOn(const SelectAll(), object: 1);
    expect(refused.did, isFalse);
    expect(refused.says, contains('needs a "level"'));
  });

  test('an argument this build does not take is refused by name', () async {
    await call('addPrimitive', <String, Object?>{'kind': 'box'});
    // `ux-43`'s own acceptance, and the bug behind it: `select {ids: [1]}`
    // used to be accepted, do nothing, and answer "nothing selected" — the
    // agent had spelled `objects` wrong and had no way to find out.
    final CallToolResult refused = await call('select', <String, Object?>{
      'ids': <int>[1],
    });
    expect(refused.isError, isTrue);
    expect(saidBy(refused), contains('"ids"'));
    expect(saidBy(refused), contains('objects'));
    // And it refused before the tool ran: the selection is still whatever
    // `addPrimitive` left, not the empty one `select` with no arguments makes.
    expect(session.history.selection.objects, <int>[1]);
  });

  test('a tool that already names its target is left alone', () async {
    await call('addPrimitive', <String, Object?>{'kind': 'box'});
    final ListToolsResult tools = await connection.listTools();
    Tool named(String name) =>
        tools.tools.firstWhere((Tool it) => it.name == name);

    // `rename` takes an id, so it is aimed already and gains nothing.
    expect(named('rename').inputSchema.properties!.keys, <String>['id', 'to']);
    // `extrude` reads the selection, so it grew the target arguments.
    expect(named('extrude').inputSchema.properties!.keys, contains('faces'));
    expect(named('extrude').inputSchema.properties!.keys, contains('object'));
    expect(
      named('deleteObjects').inputSchema.properties!.keys,
      contains('ids'),
    );
  });

  group('batch', () {
    test('runs as one step, and one undo takes the whole thing back', () async {
      final CallToolResult ran = await call('batch', <String, Object?>{
        'commands': <Map<String, Object?>>[
          <String, Object?>{'name': 'addPrimitive', 'kind': 'box'},
          <String, Object?>{'name': 'addPrimitive', 'kind': 'sphere'},
          <String, Object?>{'name': 'rename', 'id': 1, 'to': 'left'},
          <String, Object?>{'name': 'rename', 'id': 2, 'to': 'right'},
          <String, Object?>{'name': 'setParent', 'id': 2, 'to': 1},
        ],
      });
      expect(ran.isError, isNot(true), reason: saidBy(ran));
      expect(session.project.objects, hasLength(2));
      expect(session.project[2]!.parent, 1);

      final CallToolResult undone = await call('undo');
      expect(undone.isError, isNot(true), reason: saidBy(undone));
      // Mutation: five steps instead of one. A person's ⌘Z would then take
      // back a fifth of what an agent said it did, four times over.
      expect(session.project.objects, isEmpty);
    });

    test('a refusal inside it rolls the whole batch back', () async {
      await call('addPrimitive', <String, Object?>{'kind': 'box'});
      await call('rename', <String, Object?>{'id': 1, 'to': 'keep this name'});

      final CallToolResult refused = await call('batch', <String, Object?>{
        'commands': <Map<String, Object?>>[
          <String, Object?>{'name': 'rename', 'id': 1, 'to': 'changed'},
          <String, Object?>{'name': 'addPrimitive', 'kind': 'sphere'},
          // There is no object 99.
          <String, Object?>{'name': 'rename', 'id': 99, 'to': 'nothing'},
        ],
      });

      expect(refused.isError, isTrue);
      expect(saidBy(refused), contains('nothing was changed'));
      expect(saidBy(refused), contains('entry 2'));
      // Mutation: leave the first two applied. A batch that half-ran is the
      // worst of both — the agent is told it failed and the document says
      // otherwise.
      expect(session.project[1]!.name, 'keep this name');
      expect(session.project.objects, hasLength(1));
      // And nothing extra on the undo stack for a person to walk past.
      expect(session.history.undoSays, contains('rename'));
    });

    test('a refusal on the very first entry reaches past nothing', () async {
      await call('addPrimitive', <String, Object?>{'kind': 'box'});

      final CallToolResult refused = await call('batch', <String, Object?>{
        'commands': <Map<String, Object?>>[
          <String, Object?>{'name': 'rename', 'id': 99, 'to': 'nothing'},
        ],
      });
      expect(refused.isError, isTrue);
      // Mutation: undo unconditionally after a rollback. The batch left no
      // step, so the undo would take back the `addPrimitive` before it — a
      // rollback that deletes somebody's work.
      expect(session.project.objects, hasLength(1));
    });

    test(
      'an entry this build cannot read is refused before anything runs',
      () async {
        await call('addPrimitive', <String, Object?>{'kind': 'box'});
        final CallToolResult refused = await call('batch', <String, Object?>{
          'commands': <Map<String, Object?>>[
            <String, Object?>{'name': 'rename', 'id': 1, 'to': 'fine'},
            <String, Object?>{'name': 'notACommand'},
          ],
        });
        expect(refused.isError, isTrue);
        expect(saidBy(refused), contains('entry 1'));
        expect(session.project[1]!.name, 'box');
      },
    );

    test('each entry may aim itself', () async {
      await aCube();
      await call('addPrimitive', <String, Object?>{'kind': 'box'});
      await call('bakeToMesh', <String, Object?>{'id': 2});
      await call('selectNone');
      session.history.selection = const ProjectSelection();

      final CallToolResult ran = await call('batch', <String, Object?>{
        'commands': <Map<String, Object?>>[
          <String, Object?>{
            'name': 'extrude',
            'object': 1,
            'faces': <int>[0],
            'distance': 0.3,
          },
          <String, Object?>{
            'name': 'extrude',
            'object': 2,
            'faces': <int>[1],
            'distance': 0.3,
          },
        ],
      });
      expect(ran.isError, isNot(true), reason: saidBy(ran));
      expect(session.history.selection.isEmpty, isTrue);
    });

    test('an empty batch is refused by the schema, before the server', () {
      // `minItems: 1` on the tool's own schema, so a client that validates
      // says so without a round trip; `ModelSession.batch` refuses one too,
      // for the caller that reaches it in Dart.
      expect(session.batch(const <Map<String, Object?>>[]).did, isFalse);
      expect(
        session.batch(const <Map<String, Object?>>[]).says,
        contains('a batch of nothing'),
      );
    });
  });

  test('cleanup puts the selection back where it found it', () async {
    await call('addPrimitive', <String, Object?>{'kind': 'box'});
    await call('addPrimitive', <String, Object?>{'kind': 'sphere'});
    await call('bakeToMesh', <String, Object?>{'id': 1});
    await call('bakeToMesh', <String, Object?>{'id': 2});
    await call('select', <String, Object?>{
      'objects': <int>[1],
    });

    await call('cleanup');

    // Mutation: leave the cursor on whichever mesh the walk finished on.
    // That is the bug the review found: `cleanup` then `extrude` extruded
    // something nobody had asked about.
    expect(session.history.selection.objects, <int>[1]);
  });

  test(
    'the journal replays a rolled-back batch as a batch that did nothing',
    () async {
      await call('addPrimitive', <String, Object?>{'kind': 'box'});
      await call('batch', <String, Object?>{
        'commands': <Map<String, Object?>>[
          <String, Object?>{'name': 'rename', 'id': 1, 'to': 'changed'},
          <String, Object?>{'name': 'rename', 'id': 99, 'to': 'nothing'},
        ],
      });

      final String journal = '${workspace.path}/recovery.jsonl';
      await call('journal', <String, Object?>{'to': journal});

      final JournalReplay replayed = CommandJournal.replay(
        File(journal).readAsBytesSync(),
        const ModelProject(),
      );
      expect(replayed.refused, isNull, reason: replayed.refused);
      // Mutation: replay the commands and ignore the rollback. A recovery that
      // brings back an edit the live session had already taken back is worse
      // than no recovery — the person cannot tell which of the two is right.
      expect(replayed.history!.project.objects.single.name, 'box');
    },
  );
}
