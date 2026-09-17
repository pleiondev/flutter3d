/// `ux-19`'s own acceptance, over the real MCP protocol: review §5.3's
/// "cube → extrude one face → GLB" with no blind call in it.
///
/// **Blind is the word the review used and this test is about.** Every call
/// in the old version of this scenario named a number nothing had told the
/// agent: face 4, because a cube has six faces and one of them is probably the
/// top. Here the face id comes from `describe`, the pick comes from
/// `selectFacing`, and the ids of what an edit made come back in the answer's
/// own `structuredContent` rather than from calling `list` again and diffing
/// it against what the agent remembered.
///
///     dart test test/reading_state_test.dart
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
      'flutter3d_model_mcp_reading_state',
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

  test(
    'a cube, its top face found by name, extruded, with no blind call',
    () async {
      // 1. Make the cube. The answer says what it made, so nothing has to call
      //    `list` to find out the id.
      final CallToolResult made = await call('addPrimitive', <String, Object?>{
        'kind': 'box',
      });
      expect(made.isError, isNot(true), reason: saidBy(made));
      final Map<String, Object?> structured = made.structuredContent!;
      expect(structured['did'], isTrue);
      expect(structured['ids'], <int>[1], reason: 'the cube it just built');

      // 2. Convert it, so there are elements at all — and the refusal before
      //    that says which two tools get you there.
      final CallToolResult tooEarly = await call('describe', <String, Object?>{
        'id': 1,
      });
      expect(saidBy(tooEarly), contains('bakeToMesh'));
      await call('bakeToMesh', <String, Object?>{'id': 1});

      // 3. Read the faces. Every one of them says where it is and which way it
      //    points, which is the whole of what the old scenario had to guess.
      final CallToolResult described = await call('describe', <String, Object?>{
        'id': 1,
        'level': 'face',
      });
      final String faces = saidBy(described);
      expect(faces, contains('faces (6 of 6):'));
      expect(faces, contains('normal'));
      expect(faces, contains('area'));
      expect(faces, contains('bounds'));

      // 4. Into mesh mode on that object — the one id in this whole scenario
      //    that is typed, and it came back from step 1's own answer — and then
      //    pick the top face by what it is rather than by its number.
      await call('select', <String, Object?>{
        'object': 1,
        'level': 'face',
        'elements': <int>[],
      });
      final CallToolResult top = await call('selectFacing', <String, Object?>{
        'axis': <double>[0, 1, 0],
      });
      expect(top.isError, isNot(true), reason: saidBy(top));
      final Map<String, Object?> picked =
          top.structuredContent!['selection']! as Map<String, Object?>;
      expect(picked['mode'], 'mesh');
      expect(picked['level'], 'face');
      expect(picked['elements']! as List<Object?>, hasLength(1));

      // The face it picked really is the top one, as the mesh sees it.
      final int face = (picked['elements']! as List<Object?>).single! as int;
      final EditedGeometry geometry =
          session.project[1]!.geometry as EditedGeometry;
      expect(geometry.mesh.normalOf(face).y, closeTo(1.0, 1e-6));

      // 5. Extrude it, and read what that left selected out of the answer.
      final CallToolResult extruded = await call('extrude', <String, Object?>{
        'distance': 0.5,
      });
      expect(extruded.isError, isNot(true), reason: saidBy(extruded));
      final Map<String, Object?> after =
          extruded.structuredContent!['selection']! as Map<String, Object?>;
      expect(after['elements']! as List<Object?>, isNotEmpty);
      // An edit that made no object says so rather than repeating the cube's
      // own id from three calls ago.
      expect(extruded.structuredContent!['ids'], isEmpty);

      // 6. Out to a GLB.
      final String glb = '${workspace.path}/cube.glb';
      final CallToolResult written = await call('export', <String, Object?>{
        'to': glb,
      });
      expect(written.isError, isNot(true), reason: saidBy(written));
      expect(File(glb).existsSync(), isTrue);
    },
  );

  test('duplicate and separate say what they made', () async {
    await call('addPrimitive', <String, Object?>{'kind': 'box'});

    final CallToolResult copied = await call(
      'duplicateObjects',
      const <String, Object?>{},
    );
    expect(copied.isError, isNot(true), reason: saidBy(copied));
    // Mutation: leave `ids` empty and make the agent call `list` and diff it
    // against what it remembers. That diff is the bug the review found — an
    // agent that had lost track renamed the original.
    expect(copied.structuredContent!['ids'], <int>[2]);

    final CallToolResult nothing = await call('list');
    expect(
      nothing.structuredContent!['ids'],
      isEmpty,
      reason: 'a read makes nothing, and must not claim the last edit\'s work',
    );
  });

  test('a refusal is structured too, and says so', () async {
    final CallToolResult refused = await call('selectFacing', <String, Object?>{
      'axis': <double>[0, 1, 0],
    });
    expect(refused.isError, isTrue);
    expect(refused.structuredContent!['did'], isFalse);
    expect(refused.structuredContent!['says'], contains('mesh mode'));
  });

  test('list carries the parent, the place and the version', () async {
    await call('addPrimitive', <String, Object?>{'kind': 'box'});
    await call('addPrimitive', <String, Object?>{
      'kind': 'sphere',
      'at': <double>[0, 2, 0],
    });
    await call('setParent', <String, Object?>{'id': 2, 'to': 1});

    final String listing = saidBy(await call('list'));
    expect(listing, contains('1 box (parametric, v1)'));
    expect(listing, contains('under 1'));
    expect(listing, contains('at 0.000 2.000 0.000'));
    expect(listing, contains('selection:'));
  });

  test('selectNear reaches a region a rubber band would', () async {
    await call('addPrimitive', <String, Object?>{'kind': 'box'});
    await call('bakeToMesh', <String, Object?>{'id': 1});
    await call('select', <String, Object?>{
      'object': 1,
      'level': 'vertex',
      'elements': <int>[],
    });

    final CallToolResult near = await call('selectNear', <String, Object?>{
      'point': <double>[0.5, 0.5, 0.5],
      'radius': 0.1,
    });
    expect(near.isError, isNot(true), reason: saidBy(near));
    final Map<String, Object?> selection =
        near.structuredContent!['selection']! as Map<String, Object?>;
    expect(selection['elements']! as List<Object?>, hasLength(1));
    expect(selection['level'], 'vertex');
  });

  test(
    'describe names specific elements when asked, and caps when not',
    () async {
      await call('addPrimitive', <String, Object?>{'kind': 'sphere'});
      await call('bakeToMesh', <String, Object?>{'id': 1});

      final String capped = saidBy(
        await call('describe', <String, Object?>{
          'id': 1,
          'level': 'vertex',
          'limit': 3,
        }),
      );
      expect(capped, contains('vertexs (3 of '));
      expect(capped, contains('more; name them in "elements"'));

      final String named = saidBy(
        await call('describe', <String, Object?>{
          'id': 1,
          'level': 'face',
          'elements': <int>[0, 1],
        }),
      );
      expect(named, contains('faces (2 of '));
      expect(named, isNot(contains('more; name them')));
    },
  );

  test(
    'describing an object that is not there is an answer, not a crash',
    () async {
      expect(
        saidBy(await call('describe', <String, Object?>{'id': 99})),
        contains('there is no object 99'),
      );
    },
  );
}
