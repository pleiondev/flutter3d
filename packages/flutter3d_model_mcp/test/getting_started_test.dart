/// `ux-44`: what an agent that has never seen this editor is handed before it
/// calls anything — the strategy prompt, instructions that name the tools
/// worth knowing, and `describe_type` instead of "read the subtypes".
///
///     dart test test/getting_started_test.dart
library;

import 'dart:io';

import 'package:dart_mcp/client.dart';
import 'package:flutter3d_model_mcp/flutter3d_model_mcp.dart';
import 'package:stream_channel/stream_channel.dart';
import 'package:test/test.dart';

void main() {
  late Directory workspace;
  late MCPClient client;
  late ServerConnection connection;
  late InitializeResult ready;

  setUp(() async {
    workspace = Directory.systemTemp.createTempSync(
      'flutter3d_model_mcp_getting_started',
    );
    final pipe = StreamChannelController<String>(sync: true);
    ModelMcpServer(
      pipe.local,
      session: ModelSession.open('${workspace.path}/scene.f3dproj'),
    );
    client = MCPClient(
      Implementation(name: 'the suite', version: modelMcpVersion),
    );
    connection = client.connectServer(pipe.foreign);
    ready = await connection.initialize(
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

  group('the strategy prompt', () {
    test(
      'prompts/list offers it, and prompts/get returns the advice',
      () async {
        expect(ready.capabilities.prompts, isNotNull);

        final ListPromptsResult offered = await connection.listPrompts();
        final Prompt strategy = offered.prompts.singleWhere(
          (Prompt it) => it.name == 'modelling_strategy',
        );
        expect(strategy.description, isNotNull);

        final GetPromptResult got = await connection.getPrompt(
          GetPromptRequest(name: 'modelling_strategy'),
        );
        final String text = (got.messages.single.content as TextContent).text;

        // Mutation: offer a prompt that repeats the tool list. The thing a
        // tool table cannot say is the order, and each of these is a step of
        // it — read before editing, aim before acting, look at the result,
        // group what belongs together, check before exporting.
        for (final String named in <String>[
          'describe',
          'selectFacing',
          'render',
          'amend',
          'batch',
          'cleanup',
          'check',
        ]) {
          expect(
            text,
            contains(named),
            reason: 'the strategy never mentions $named',
          );
        }
      },
    );
  });

  group('the instructions', () {
    test('name the tools an agent would not find on its own', () {
      final String? said = ready.instructions;
      expect(said, isNotNull);
      for (final String named in <String>[
        'describe',
        'render',
        'renderSheet',
        'amend',
        'batch',
        'cleanup',
        'makeGameReady',
        'buildFrom',
        'describe_type',
        'modelling_strategy',
      ]) {
        expect(
          said,
          contains(named),
          reason: 'instructions never mention $named',
        );
      }
      // And say what the numbers mean, since every one of them is a number
      // in something.
      expect(said, contains('metres'));
      expect(said, contains('Y-up'));
      // Fifteen to twenty lines, not a manual: an agent reads this before it
      // has a reason to care about any of it.
      final int lines = said!
          .trim()
          .split('\n')
          .where((String it) => it.trim().isNotEmpty)
          .length;
      expect(lines, lessThan(40));
    });
  });

  group('describe_type', () {
    Future<String> call(Map<String, Object?> arguments) async {
      final CallToolResult result = await connection.callTool(
        CallToolRequest(name: 'describe_type', arguments: arguments),
      );
      return (result.content.single as TextContent).text;
    }

    test('a family alone lists its kinds', () async {
      final String said = await call(<String, Object?>{'family': 'modifier'});
      for (final String kind in <String>[
        'array',
        'mirror',
        'smooth',
        'subdivision',
        'boolean',
      ]) {
        expect(said, contains(kind));
      }
    });

    test(
      'a kind lists its own fields, with the ranges an inspector uses',
      () async {
        final String said = await call(<String, Object?>{
          'family': 'modifier',
          'kind': 'array',
        });
        // Mutation: hand back the paragraph inside `addModifier`'s description.
        // That paragraph covers five kinds in three hundred words and an agent
        // has to read all of it to find the two fields it wants.
        expect(said, contains('count'));
        expect(said, contains('offset'));
        expect(said, contains('mergeDistance'));
        // The hint table's own range, which is where the panel's slider comes
        // from — so the two cannot disagree.
        expect(said, contains('1 to 64'));
      },
    );

    test('shapes and texture nodes answer the same way', () async {
      expect(
        await call(<String, Object?>{'family': 'shape'}),
        contains('cuboid'),
      );
      expect(
        await call(<String, Object?>{'family': 'shape', 'kind': 'torus'}),
        contains('radius'),
      );
      expect(
        await call(<String, Object?>{'family': 'textureNode'}),
        contains('blend'),
      );
      expect(
        await call(<String, Object?>{
          'family': 'textureNode',
          'kind': 'levels',
        }),
        contains('gamma'),
      );
    });

    test('a name it does not have is an answer naming what there is', () async {
      expect(
        await call(<String, Object?>{'family': 'modifier', 'kind': 'bevel'}),
        allOf(contains('not a modifier'), contains('array')),
      );
    });
  });

  group('render takes a size', () {
    test('a smaller picture is a smaller picture', () async {
      await connection.callTool(
        CallToolRequest(
          name: 'addPrimitive',
          arguments: <String, Object?>{'kind': 'box'},
        ),
      );

      Future<int> bytesAt(int size) async {
        final CallToolResult result = await connection.callTool(
          CallToolRequest(
            name: 'render',
            arguments: <String, Object?>{'size': size},
          ),
        );
        // `Content` is an extension type over a plain map, so `whereType`
        // cannot tell a picture from a sentence — the picture is the second
        // item, which is the order `pictureResultOf` writes them in.
        final ImageContent image = result.content.last as ImageContent;
        return image.data.length;
      }

      // Mutation: ignore `size` and always draw 512. A picture is the most
      // expensive thing this server can answer with, and "is the cube still
      // a cube" does not need a big one.
      expect(await bytesAt(128), lessThan(await bytesAt(512)));
    });

    test('an absurd size is clamped rather than refused', () async {
      await connection.callTool(
        CallToolRequest(
          name: 'addPrimitive',
          arguments: <String, Object?>{'kind': 'box'},
        ),
      );
      final CallToolResult result = await connection.callTool(
        CallToolRequest(
          name: 'render',
          arguments: <String, Object?>{'size': 100000},
        ),
      );
      expect(
        result.isError,
        isNot(true),
        reason: (result.content.first as TextContent).text,
      );
      expect((result.content.first as TextContent).text, contains('1024×1024'));
    });
  });
}
